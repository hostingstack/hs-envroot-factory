$config[:vm_ip_address] = "10.20.0.%d" % (2 + $worker_id)
$config[:redis] = 'redis://localhost:6379'
