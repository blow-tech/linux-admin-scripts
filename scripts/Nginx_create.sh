#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "Only root allowed." 
   exit 1
fi

TEMPLATE_HTTP="/root/template/nginx-http.conf"
TEMPLATE_HTTPS="/root/template/nginx-secure-http.conf"

if [ ! -f "$TEMPLATE_HTTP" ] || [ ! -f "$TEMPLATE_HTTPS"]; then
    echo "Template files not found."
    exit 1
fi

read -p "Enter vhost (contoh: example.test): " vhost

# Ask user to choice between HTTP or HTTPS template
echo "Want to use HTTP or HTTPS?"
echo "1) HTTP Only"
echo "2) HTTP + HTTPS"
read -p "Choice between (1) or (2): " template_choice

if [ "$template_choice" == "1" ]; then
    TEMPLATE_FILE="$TEMPLATE_HTTP"
elif [ "$template_choice" == "2" ]; then
    TEMPLATE_FILE="$TEMPLATE_HTTPS"
else
    echo "Wrong choice!"
    exit 1
fi

# Create new vhost directory on /var/www/
mkdir -p /var/www/$vhost
chown -R baiquni:baiquni /var/www/$vhost

# Create nginx configuration base on template on sites-available
echo "Membuat file konfigurasi nginx untuk $vhost dari template..."
sed "s/{{DOMAIN}}/$vhost/g" "$TEMPLATE_FILE" > /etc/nginx/sites-available/$vhost

# Create symlinks into sites-enabled
ln -s /etc/nginx/sites-available/$vhost /etc/nginx/sites-enabled/

# Check nginx configuration
nginx -t

if [ $? -eq 0 ]; then
    systemctl reload nginx
    echo "Setup vhost $vhost done!"
else
    echo "Error found. Only God know where."
fi
