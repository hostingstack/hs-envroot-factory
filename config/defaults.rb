# -*- mode: ruby -*-
$config = {}
$config[:template_cache] = File.expand_path('../../template_cache/', __FILE__)
$config[:file_store] = File.expand_path('../../files/', __FILE__)
$config[:openvz_etc] = '/etc/vz'
$config[:openvz_root] = '/var/lib/vz/root'
$config[:openvz_private] = '/var/lib/vz/private'
$config[:vm_ip_address] = "10.20.0.%d" % (2 + $worker_id)
$config[:vm_id] = 9000 + $worker_id
$config[:vm_app_code_path] = '/app/code'
$config[:vm_app_home] = '/app'
$config[:vm_app_user] = 'app'
$config[:vm_nameserver] = ["8.8.8.8"]
$config[:vm_http_proxy] = 'http://%s:3128' % SocketSupport.local_ip
$config[:redis] = 'redis://localhost:6379'
$config[:apt_sources] = <<EOSOURCES
deb http://cdn.debian.net/debian squeeze main non-free contrib
deb http://cdn.debian.net/debian squeeze-updates main non-free contrib
deb http://security.debian.org/ squeeze/updates main non-free contrib
deb http://repository.example.org/ appplatform main
EOSOURCES

