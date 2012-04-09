require 'fileutils'
require 'yaml'

class Recipe::Php < Recipe
  def version
    1
  end

  def template_name
    facts['runtime']
  end

  def install_php
    install_deb ["apache2-mpm-prefork", "libapache2-mod-php5", "php5-mysql", "php5-pgsql", "php5-imagick",
                 "php5-memcache", "php5-memcached", "php5-gd", "php5-intl", "php5-suhosin", "php-apc",
                 "php-pear", "libphp-adodb", "php5-mcrypt", "php5-curl"]
    File.unlink "/etc/init.d/apache2"
  end

  def write_glue(opts = {})
    tpl = <<EOT
#!/bin/sh
export HOME=%vm_app_code_path%
. /etc/profile
rm -f /tmp/pid /tmp/accept.lock /tmp/log
cd %vm_app_code_path%
. %vm_app_home%/config_vars
exec /usr/sbin/apache2 -f /etc/apache2-app.conf
EOT
    file_content "/bin/startup", tpl, opts
    file_chmod "/bin/startup", 0755

    tpl = <<EOT
LockFile /tmp/accept.lock
PidFile /tmp/pid
Timeout 30
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 15
StartServers          1
MinSpareServers       1
MaxSpareServers       1
MaxClients          150
MaxRequestsPerChild 1000
User app
Group app
Listen 8080
DefaultType text/plain
HostnameLookups Off
LogFormat "%h %l %u %t \\"%r\\" %>s %O \\"%{Referer}i\\" \\"%{User-Agent}i\\"" combined
CustomLog "|/usr/bin/logger -t apache2 -i -p local6.notice" combined
ErrorLog syslog
LogLevel warn
ServerTokens Prod
ServerSignature Off
TraceEnable Off

AccessFileName .htaccess
<Files ~ "^\.ht">
Order allow,deny
Deny from all
Satisfy all
</Files>
<Directory />
Options None
AllowOverride None
Order Deny,Allow
Deny from all
</Directory>
<Directory %doc_root%>
Options +FollowSymLinks
AllowOverride All
Order Allow,Deny
Allow from all
</Directory>
DocumentRoot %doc_root%

LoadModule alias_module /usr/lib/apache2/modules/mod_alias.so
LoadModule auth_basic_module /usr/lib/apache2/modules/mod_auth_basic.so
LoadModule authn_file_module /usr/lib/apache2/modules/mod_authn_file.so
LoadModule authz_default_module /usr/lib/apache2/modules/mod_authz_default.so
LoadModule authz_groupfile_module /usr/lib/apache2/modules/mod_authz_groupfile.so
LoadModule authz_host_module /usr/lib/apache2/modules/mod_authz_host.so
LoadModule authz_user_module /usr/lib/apache2/modules/mod_authz_user.so
LoadModule autoindex_module /usr/lib/apache2/modules/mod_autoindex.so
LoadModule deflate_module /usr/lib/apache2/modules/mod_deflate.so
LoadModule dir_module /usr/lib/apache2/modules/mod_dir.so
LoadModule env_module /usr/lib/apache2/modules/mod_env.so
LoadModule mime_module /usr/lib/apache2/modules/mod_mime.so
LoadModule reqtimeout_module /usr/lib/apache2/modules/mod_reqtimeout.so
LoadModule setenvif_module /usr/lib/apache2/modules/mod_setenvif.so
LoadModule rewrite_module /usr/lib/apache2/modules/mod_rewrite.so

DirectoryIndex index.html index.php index.xhtml index.htm
TypesConfig /etc/mime.types
AddType application/x-compress .Z
AddType application/x-gzip .gz .tgz
AddType application/x-bzip2 .bz2
AddType text/html .shtml
AddOutputFilterByType DEFLATE text/html text/plain text/xml
AddOutputFilterByType DEFLATE text/css
AddOutputFilterByType DEFLATE application/x-javascript application/javascript application/ecmascript
AddOutputFilterByType DEFLATE application/rss+xml
AddOutputFilter INCLUDES .shtml

LoadModule php5_module /usr/lib/apache2/modules/libphp5.so
<FilesMatch "\.ph(p3?|tml)$">
SetHandler application/x-httpd-php
</FilesMatch>
EOT
    file_content "/etc/apache2-app.conf", tpl, opts
    file_chmod "/etc/apache2-app.conf", 0640

    file_content "/etc/php5/apache2/conf.d/error.ini", <<EOT
error_reporting  =  E_ALL & ~E_NOTICE
display_errors = Off
display_startup_errors = Off
log_errors = On
log_errors_max_len = 0
ignore_repeated_errors = Off
ignore_repeated_source = Off
report_memleaks = On
track_errors = Off
error_log = syslog
EOT
    file_chmod "/etc/php5/apache2/conf.d/error.ini", 0640

    file_content "/bin/logcollect", <<EOT
#!/bin/sh
cat /tmp/log
truncate --size=0 /tmp/log
EOT
    file_chmod "/bin/logcollect", 0755

  end

end
