# exit on first error
set -e

# setup nginx
sudo apt-get install nginx -qy

if [ ! -f /etc/nginx/sites-enabled/belljust.in ]; then
    sudo ln -s `pwd`/config/nginx/belljust.in /etc/nginx/sites-enabled/belljust.in
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo nginx reload
fi

# certbot for SSL certificates
sudo apt-get install software-properties-common -qy
sudo add-apt-repository ppa:certbot/certbot
sudo apt-get update
sudo apt-get install python-certbot-nginx -qy
sudo certbot --nginx certonly

# install hugo
if [ ! -f /usr/local/bin/hugo ]; then
    wget -qO hugo.tar.gz https://github.com/gohugoio/hugo/releases/download/v0.40/hugo_0.40_Linux-64bit.tar.gz
    mkdir .hugotmp && tar -xf hugo.tar.gz -C .hugotmp && rm hugo.tar.gz

    sudo mv .hugotmp/hugo /usr/local/bin/
    rm -rf .hugotmp
fi

hugo
