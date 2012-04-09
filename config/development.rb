$config[:vm_ip_address] = "10.20.0.%d" % (2 + $worker_id)
$config[:redis] = 'redis://localhost:6379'
$config[:apt_sources_EXAMPLE] = <<EOSOURCES
deb http://apt-cache.example.org/ftp.at.debian.org/debian squeeze main non-free contrib
deb http://apt-cache.example.org/ftp.at.debian.org/debian squeeze-updates main non-free contrib
deb http://apt-cache.example.org/security.debian.org/ squeeze/updates main non-free contrib
deb http://apt-cache.example.org/repository.example.org/ appplatform main
EOSOURCES

