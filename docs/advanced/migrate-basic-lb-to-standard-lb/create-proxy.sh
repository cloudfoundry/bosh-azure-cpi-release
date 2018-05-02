#!/bin/bash

rg_name=$1
avset_name=$2
basic_lb_name=$3
standard_sku_ip_address=$4
proxy_vm_name="proxy"

vm_id=$(az vm availability-set show --resource-group ${rg_name} --name ${avset_name} | jq '.virtualMachines[0].id' -r)
vm_size=$(az vm show --ids "${vm_id}" | jq '.hardwareProfile.vmSize' -r)
az vm create --resource-group ${rg_name} --name ${proxy_vm_name} --image UbuntuLTS --size ${vm_size} --availability-set ${avset_name} --generate-ssh-keys
az vm open-port --port 80 --priority 900 --resource-group ${rg_name} --name ${proxy_vm_name}
az vm open-port --port 443 --priority 901 --resource-group ${rg_name} --name ${proxy_vm_name}
az vm open-port --port 4443 --priority 902 --resource-group ${rg_name} --name ${proxy_vm_name}
proxy_vm_ip=$(az vm list-ip-addresses --resource-group ${rg_name} --name ${proxy_vm_name} | jq '.[].virtualMachine.network.publicIpAddresses[0].ipAddress' -r)
echo "The proxy VM IP address is ${proxy_vm_ip}"
basic_lb_backend_id=$(az network lb show --resource-group ${rg_name} --name ${basic_lb_name} | jq '.backendAddressPools[0].id' -r)
az network nic ip-config address-pool add --resource-group ${rg_name} --nic-name "${proxy_vm_name}VMNic" --ip-config-name "ipconfig${proxy_vm_name}" --address-pool "${basic_lb_backend_id}"

ssh ${proxy_vm_ip} "sudo apt-get update"
ssh ${proxy_vm_ip} "sudo apt-get -y install haproxy"
cat > haproxy.cfg << EOF
global
        log /dev/log    local0
        log /dev/log    local1 notice
        chroot /var/lib/haproxy
        stats socket /run/haproxy/admin.sock mode 660 level admin
        stats timeout 30s
        user haproxy
        group haproxy
        daemon

        # Default SSL material locations
        ca-base /etc/ssl/certs
        crt-base /etc/ssl/private

        # Default ciphers to use on SSL-enabled listening sockets.
        # For more information, see ciphers(1SSL). This list is from:
        #  https://hynek.me/articles/hardening-your-web-servers-ssl-ciphers/
        ssl-default-bind-ciphers ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:ECDH+3DES:DH+3DES:RSA+AESGCM:RSA+AES:RSA+3DES:!aNULL:!MD5:!DSS
        ssl-default-bind-options no-sslv3

defaults
        log     global
        mode    http
        option  httplog
        option  dontlognull
        timeout connect 5000
        timeout client  50000
        timeout server  50000
        errorfile 400 /etc/haproxy/errors/400.http
        errorfile 403 /etc/haproxy/errors/403.http
        errorfile 408 /etc/haproxy/errors/408.http
        errorfile 500 /etc/haproxy/errors/500.http
        errorfile 502 /etc/haproxy/errors/502.http
        errorfile 503 /etc/haproxy/errors/503.http
        errorfile 504 /etc/haproxy/errors/504.http

listen httpserver
    bind *:80
    mode tcp
    server httpserver ${standard_sku_ip_address}:80
 
listen httpsserver
    bind *:443
    mode tcp
    server httpsserver ${standard_sku_ip_address}:443

listen logserver
    bind *:4443
    mode tcp
    server logserver ${standard_sku_ip_address}:4443
EOF
scp haproxy.cfg ${proxy_vm_ip}:~/haproxy.cfg
ssh ${proxy_vm_ip} "sudo chmod 666 /etc/haproxy/haproxy.cfg"
ssh ${proxy_vm_ip} "sudo mv ~/haproxy.cfg /etc/haproxy/haproxy.cfg"
ssh ${proxy_vm_ip} "sudo service haproxy restart"

cat > probe-server.py <<EOF
from http.server import HTTPServer, BaseHTTPRequestHandler


class SimpleHTTPRequestHandler(BaseHTTPRequestHandler):

    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'Hello, world!')


httpd = HTTPServer(('', 8080), SimpleHTTPRequestHandler)
httpd.serve_forever()
EOF
scp probe-server.py ${proxy_vm_ip}:~/probe-server.py

rm haproxy.cfg
rm probe-server.py
