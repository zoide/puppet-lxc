# defined container from host
define lxc::vm (
  $ensure          = 'present',
  $ip              = 'dhcp',
  $mac             = '',
  $gw              = '',
  $netmask         = '255.255.255.0',
  $passwd,
  $distrib         = $::lsbdistcodename,
  $container_root  = '/var/lib/lxc',
  $mainuser        = '',
  $mainuser_sshkey = '',
  $autorun         = true,
  $bridge          = $lxc::controlling_host::bridge,
  $addpackages     = '',
  $autostart       = true) {
  require 'lxc::controlling_host'

  File {
    ensure => $ensure, }
  $c_path = "${container_root}/${name}"
  $h_name = $name
  $mac_r = $mac ? {
    ''      => lxc_genmac($h_name),
    default => $mac,
  }

  file {
    $c_path:
      ensure => $ensure ? {
        'present' => 'directory',
        default   => 'absent',
      } ;

    "${c_path}/preseed.cfg":
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => template('lxc/preseed.cfg.erb');
  }

  if $ip != 'manual' {
    file { "${c_path}/rootfs/etc/network/interfaces":
      owner     => 'root',
      group     => 'root',
      mode      => '0644',
      require   => Exec["create ${h_name} container"],
      subscribe => Exec["create ${h_name} container"],
      content   => template('lxc/interface.erb');
    }
  }

  if defined(Class['dnsmasq']) {
    dnsmasq::dhcp-host { "${h_name}-${mac_r}":
      hostname => $name,
      mac      => $mac_r,
    }
  }

  if $addpackages != '' {
    $addpkg = "-a ${addpackages}"
  }

  if $ensure == 'present' {
    exec { "create ${h_name} container":
      command     => "/bin/bash ${lxc::mdir}/templates/lxc-debian -p ${c_path} -n ${h_name} -d ${distrib} ${addpkg}",
      require     => File["${c_path}/preseed.cfg"],
      refreshonly => false,
      creates     => "${c_path}/config",
      logoutput   => true,
      timeout     => 720,
    }

    Common::Line {
      require => Exec["create ${h_name} container"],
      file    => "${c_path}/config",
    }

    Replace {
      require => Exec["create ${h_name} container"], }

    common::line {
      "mac: ${mac_r}":
        line => "lxc.network.hwaddr = ${mac_r}";

      "bridge: ${mac_r}:${lxc::controlling_host::bridge}":
        line => "lxc.network.link = ${bridge}";

      "pair: {${mac_r}:${h_name}":
        line   => "lxc.network.veth.pair = veth_${h_name}",
        ensure => 'absent';

      "send host-name \"${h_name}\";":
        file => "${c_path}/rootfs/etc/dhcp/dhclient.conf";
    }

    exec { "etc_hostname: ${h_name}":
      command     => "echo ${h_name} > ${c_path}/rootfs/etc/hostname",
      subscribe   => Exec["create ${h_name} container"],
      refreshonly => true,
    }

    # # setting the root-pw
    # echo 'root:root' | chroot $rootfs chpasswd
    exec { "set_rootpw: ${h_name}":
      command     => "echo \'root:${passwd}\' | chroot ${c_path}/rootfs chpasswd",
      refreshonly => true,
      require     => Exec["create ${h_name} container"],
      subscribe   => Exec["create ${h_name} container"],
    }

    # # Disable root - login via ssh
    replace { "sshd_noRootlogin: ${h_name}":
      file        => "${c_path}/rootfs/etc/ssh/sshd_config",
      pattern     => 'PermitRootLogin yes',
      replacement => 'PermitRootLogin no',
    }

    if $mainuser != '' and $mainuser_sshkey != '' {
      exec { "${h_name}::useradd_${mainuser}":
        command     => "chroot ${c_path}/rootfs useradd -s /bin/bash -g users -G adm -c \"Admin user\" ${mainuser}",
        subscribe   => Exec["create ${h_name} container"],
        refreshonly => true,
      }

      common::line { "${h_name}::mongrify_sudoers":
        line    => '%adm ALL=(ALL) NOPASSWD: ALL',
        file    => "${c_path}/rootfs/etc/sudoers",
        require => Exec["${h_name}::useradd_${mainuser}"],
      }
      # # create ssh dir for user
      $ssh_dir = "${c_path}/rootfs/home/${mainuser}/.ssh"

      exec { "${h_name}::sshkey_${mainuser}":
        command     => "mkdir -p ${ssh_dir} && echo \"${mainuser_sshkey}\" > ${ssh_dir}/authorized_keys && chroot ${c_path}/rootfs chown -R ${mainuser}:users /home/${mainuser}",
        subscribe   => Exec["${h_name}::useradd_${mainuser}"],
        unless      => "test -e ${ssh_dir}/.ssh/authorized_keys",
        refreshonly => true,
      }

      exec { "${h_name}::install-puppet":
        command     => "sed -i -e 's/exit\ 0//' ${c_path}/rootfs/etc/rc.local && echo 'apt-get -y update && apt-get  -o Dpkg::Options::=\"--force-confdef\" -o Dpkg::Options::=\"--force-confold\" -y install facter puppet' >>${c_path}/rootfs/etc/rc.local",
        subscribe   => Exec["create ${h_name} container"],
        refreshonly => true,
      }
    }

    if $autostart {
      exec { "/usr/bin/lxc-start -n ${h_name} -d":
        onlyif  => "/usr/bin/lxc-info -n ${h_name} 2>/dev/null | grep -q STOPPED",
        require => [
          Exec["create ${h_name} container"],
          Exec["${h_name}::install-puppet"]],
      }
    }
  } # end ensure=present



  file { "/etc/lxc/auto/${h_name}.conf":
    target => "/var/lib/lxc/${h_name}/config",
    ensure => $autorun ? {
      true  => "present",
      false => "absent",
    }
  }
}
