#! /bin/bash
read PROJECT_ID
# upload to cloud-storage 
gcloud config set project $PROJECT_ID
gcloud services enable compute.googleapis.com  iam.googleapis.com cloudresourcemanager.googleapis.com
echo "CREATING THE BUCKET TO STAGE THE APP FILES AND THE COPY TO GOOGLE COMPUTE ENGINE"
BUCKET_NAME=$PROJECT_ID-portfolio
gsutil mb gs://$BUCKET_NAME
cd html-files 
gsutil -m cp -r  .  gs://$BUCKET_NAME/app-files/html-files
cd ../scripts
gsutil cp nginx.conf gs://$BUCKET_NAME/app-files/nginx-conf 
sed -i "s/BUCKET_NAME/${BUCKET_NAME}/g" start-up-script.sh 
cd ../terraform-files
