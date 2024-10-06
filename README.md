# aws-app

前提としてドメイン取得済みでAWSに登録済みであること

## minecraft_server_aws

cd ./minecraft_server_aws/EC2
./keygen.sh

cd tf/
cp template_terraform.tfvars terraform.tfvars
<!-- 複製後、中身を書くこと -->

terraform init
terraform plan

terraform apply -auto-approve
./output_dump.sh

cd ../
./script.sh init
./script.sh exec
sudo docker logs mc_server

### MCRCON Command Note

./script.sh rcon
list
say

## Backup Restore
<!-- SSHで実行 -->
cd ~/minecraft
rm -rf data/*
tar -xvzf <該当のtgzファイル> -C ../data/
