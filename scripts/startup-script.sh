#! /bin/bash
apt-get update 
apt-get install -y nginx
mkdir /srv/portfolio
gsutil cp -r  gs://BUCKET_NAME/app-files/html-files/* /srv/portfolio/
gsutil cp  gs://BUCKET_NAME/app-files/nginx-conf /etc/nginx/nginx.conf
service nginx restart
