echo "ALERTA: Diversos erros podem aparecer no terminal, ignore-os."

escolherVPC(){
    local vpc_id=$(aws ec2 describe-vpcs \
        --query "Vpcs[$1].VpcId" \
        --output text)
    echo "$vpc_id"
}

escolherSubNet(){
    local subnet_id=$(aws ec2 describe-subnets \
        --query "Subnets[?VpcId=='$VPC_ID'].[SubnetId]" \
        --output text | head -n1)
    echo "$subnet_id"
}

definirParDeChaves(){
    aws ec2 describe-key-pairs --key-names "$1" --query "KeyPairs[0].KeyName" --output text
    if [ $? -eq 0 ]; then
        if [ ! -f "$1.pem" ]; then
            aws ec2 delete-key-pair --key-name "$1"

            local APAGAR_DB=$(aws ec2 describe-instances \
                --filters "Name=tag:Name,Values=$2" \
                    "Name=key-name,Values=$1" \
                    "Name=instance-state-name,Values=running" \
                --query "Reservations[].Instances[0].InstanceId" \
                --output text)

            if [ $? -eq 0 ]; then
                aws ec2 terminate-instances --instance-ids "$APAGAR_DB"
            fi

            aws ec2 create-key-pair \
            --key-name "$1" \
            --region us-east-1 \
            --query 'KeyMaterial' \
            --output text > "$1.pem"
        fi
    else
        rm -f "$1.pem"
        aws ec2 create-key-pair \
        --key-name "$1" \
        --region us-east-1 \
        --query 'KeyMaterial' \
        --output text > "$1.pem"
    fi 
    chmod 400 "$1.pem"
}

definirGrupoDeSeguranca(){
    SG_ID=$(aws ec2 describe-security-groups \
        --query "SecurityGroups[?GroupName=='$1'].GroupId" \
        --output text)
    
    if [ $? -ne 0 ]; then
        SG_ID=$(aws ec2 create-security-group \
        --group-name "$1" \
        --vpc-id $VPC_ID \
        --description "Grupo de seguranca do $2" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=sg-$3}]" \
        --query 'GroupId' \
        --output text)
        
        aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --ip-permissions "[
            {
                \"IpProtocol\": \"tcp\",
                \"FromPort\": $4,
                \"ToPort\": $4,
                \"IpRanges\": [{\"CidrIp\": \"0.0.0.0/0\"}]
            },
            {
                \"IpProtocol\": \"tcp\",
                \"FromPort\": 22,
                \"ToPort\": 22,
                \"IpRanges\": [{\"CidrIp\": \"0.0.0.0/0\"}]
            }
        ]"
    fi

    echo "$SG_ID"
}

criarScriptDeInicializacao(){
    cat << 'EOF'
    #!/bin/bash

    sudo apt-get update
    sudo apt-get install ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update

    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    sudo groupadd docker
    sudo usermod -aG docker $USER
    newgrp docker

EOF
}

criarInstancia(){
    INSTANCIA_ID=$(aws ec2 describe-instances \
                    --filters "Name=tag:Name,Values=instancia-$1" \
                             "Name=key-name,Values=$2" \
                             "Name=instance-state-name,Values=running" \
                    --query "Reservations[].Instances[0].InstanceId" \
                    --output text)
    
    if [ $? -ne 0 ] || [ -z "$INSTANCIA_ID" ]; then
        INSTANCIA_ID=$(aws ec2 run-instances \
            --image-id "$3" \
            --count 1 \
            --security-group-ids "$6" \
            --instance-type "$4" \
            --subnet-id "$SUBNET_ID" \
            --key-name "$2" \
            --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=instancia-$1}]" \
            --user-data file://"$5.txt" \
            --query 'Instances[0].InstanceId' \
            --output text
        )
    fi
    echo "$INSTANCIA_ID"
}

alocarIpElastico(){
    local IP=$(aws ec2 describe-addresses \
        --query "Addresses[?InstanceId=='$1'].PublicIp" \
        --output text)
    
    if [ -n "$IP" ]; then
        echo "$IP"
    else
        local EIP=$(aws ec2 describe-addresses --query "Addresses[?AssociationId==null].PublicIp | [0]" --output text)
        if [ $? -ne 0 ] || [ "$IP" = "None" ]; then
            aws ec2 associate-address \
                --instance-id "$1" \
                --public-ip "$EIP" \
                --query 'AssociationId' \
                --output text
        else
            local EIP=$(aws ec2 allocate-address \
                --domain vpc \
                --query 'PublicIp' \
                --output text)
            
            aws ec2 associate-address \
                --instance-id "$1" \
                --public-ip "$EIP" \
                --query 'AssociationId' \
                --output text
            
        fi
        echo "$EIP"
    fi
}