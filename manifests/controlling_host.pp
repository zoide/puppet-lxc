class lxc::controlling_host ($ensure = 'present', $provider = '', $bridge) {
  class { 'lxc': ensure => $ensure }

  package { [
    'lxc',
    'lvm2',
    'bridge-utils',
    'debootstrap']:
    ensure => $ensure;
  }

  File {
    ensure => $ensure,
    owner  => 'root',
    group  => 'root',
  }

  file { '/etc/default/lxc': source => 'puppet:///modules/lxc/etc_default_lxc', 
  }

  file {
    [
      '/cgroup',
      $lxc::mdir,
      "${lxc::mdir}/templates"]:
      ensure => 'directory';

    '/etc/sysctl.d/ipv4_forward.conf':
      source => 'puppet:///modules/lxc/etc/sysctl.conf',
      mode   => '0444';

    '/usr/local/bin/build_vm':
      content => template('lxc/build_vm.erb'),
      mode    => '0555';

    '/etc/default/grub':
      source => 'puppet:///modules/lxc/etc_default_grub',
      mode   => '0444';

    "${lxc::mdir}/templates/lxc-debian":
      recurse => true,
      content => template('lxc/lxc-debian.erb'),
      require => File["${lxc::mdir}/templates"];
  }

  exec { '/usr/sbin/update-grub':
    command     => '/usr/sbin/update-grub',
    refreshonly => true,
    subscribe   => File['/etc/default/grub'];
  }
  $mtpt = $::lsbdistcodename ? {
    'oneiric' => '/sys/fs/cgroup',
    default   => '/cgroup',
  }

  mount { 'mount_cgroup':
    ensure   => 'mounted',
    name     => $mtpt,
    atboot   => true,
    device   => 'cgroup',
    fstype   => 'cgroup',
    options  => 'defaults',
    remounts => false;
  }
}
