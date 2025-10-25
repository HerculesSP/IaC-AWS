#!/bin/bash

escolherVPC(){
    local vpc_id=$(aws ec2 describe-vpcs \
        --query "Vpcs[$1].VpcId" \
        --output text)
    echo >&2 "VPC encontrada."
    echo "$vpc_id"
}

escolherSubNet(){
    local subnet_id=$(aws ec2 describe-subnets \
        --query "Subnets[?VpcId=='$VPC_ID'].[SubnetId]" \
        --output text | head -n1)
    echo >&2 "Subrede encontrada."
    echo "$subnet_id"
}

definirParDeChaves(){
    aws ec2 describe-key-pairs --key-names "$1" --query "KeyPairs[0].KeyName" --output text > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        if [ ! -f "$1.pem" ]; then
            aws ec2 delete-key-pair --key-name "$1" --output text > /dev/null 2>&1
            echo >&2 "Par de chaves "$1" apagado, pois não se encontra no diretório."
            local APAGAR=$(aws ec2 describe-instances \
                --filters "Name=tag:Name,Values=$2" \
                    "Name=key-name,Values=$1" \
                    "Name=instance-state-name,Values=running" \
                --query "Reservations[].Instances[0].InstanceId" \
                --output text)
            if [ $? -eq 0 ]; then
                aws ec2 terminate-instances --instance-ids "$APAGAR" --output text > /dev/null 2>&1
                echo >&2 "Instância associada ao par de chaves excluido foi apagada."
            fi

            aws ec2 create-key-pair \
            --key-name "$1" \
            --region us-east-1 \
            --query 'KeyMaterial' \
            --output text > "$1.pem"
            echo >&2 "Novo par de chaves "$1" criado."
        else 
            echo >&2 "Par de chaves "$1" já se encontra criado."
        fi
    else
        rm -f "$1.pem"
        aws ec2 create-key-pair \
        --key-name "$1" \
        --region us-east-1 \
        --query 'KeyMaterial' \
        --output text > "$1.pem"
        echo >&2 "Novo par de chaves "$1" criado."
    fi 
    chmod 400 "$1.pem"
}

criarGrupoDeSeguranca() {
    local nome_grupo="$1"
    local descricao="$2"
    local vpc_id="$3"
    local tag="$4"

    SG_ID=$(aws ec2 describe-security-groups \
        --query "SecurityGroups[?GroupName=='$nome_grupo'].GroupId" \
        --output text)

    if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
        SG_ID=$(aws ec2 create-security-group \
            --group-name "$nome_grupo" \
            --vpc-id "$vpc_id" \
            --description "$descricao" \
            --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=sg-$tag}]" \
            --query 'GroupId' \
            --output text)
        echo >&2 "Grupo de segurança "${nome_grupo}" criado: "${SG_ID}""
    else
        echo >&2 "Grupo de segurança "${nome_grupo}" existente: "${SG_ID}""
    fi

    echo "$SG_ID"
}

adicionarRegraAoGrupo() {
    local sg_id="$1"
    local porta="$2"
    local protocolo="${3:-tcp}" 

    local regra_existente=$(aws ec2 describe-security-group-rules \
    --filters Name="group-id",Values="$sg_id" \
    --query "SecurityGroupRules[?FromPort == \`${porta}\` && ToPort == \`${porta}\` && CidrIpv4 == '0.0.0.0/0']" \
    --output text)

    if [ "$regra_existente" = "None" ] || [ -z "$regra_existente" ]; then
        echo "Adicionando regra de entrada: porta $porta"
        aws ec2 authorize-security-group-ingress \
            --group-id "$sg_id" \
            --ip-permissions "[
                {
                    \"IpProtocol\": \"$protocolo\",
                    \"FromPort\": $porta,
                    \"ToPort\": $porta,
                    \"IpRanges\": [{\"CidrIp\": \"0.0.0.0/0\"}]
                }
            ]" \
            --output text > /dev/null 2>&1
    else
        echo "Regra de porta $porta já existente no grupo $sg_id"
    fi
}

criarScriptDeInicializacao(){
    cat << EOF > ./tmp/inicializacao.txt
#!/bin/bash

apt-get update -y
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update

apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

groupadd docker
usermod -aG docker $USER
newgrp docker

EOF
}

criarInstancia(){
    local nome="$1"
    local chave="$2"
    local ami="$3"
    local tipo="$4"
    local grupo="$5"

    INSTANCIA_ID=$(aws ec2 describe-instances \
                    --filters "Name=tag:Name,Values=instancia-$nome" \
                             "Name=key-name,Values=$chave" \
                             "Name=instance-state-name,Values=running" \
                    --query "Reservations[].Instances[0].InstanceId" \
                    --output text)
    
    if [ $? -ne 0 ] || [ -z "$INSTANCIA_ID" ]; then
        INSTANCIA_ID=$(aws ec2 run-instances \
            --image-id "$ami" \
            --count 1 \
            --security-group-ids "$grupo" \
            --instance-type "$tipo" \
            --subnet-id "$SUBNET_ID" \
            --key-name "$2" \
            --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=instancia-$nome}]" \
            --user-data "file://./temp/inicializacao.txt" \
            --query 'Instances[0].InstanceId' \
            --output text
            echo >&2 "Instância-$nome criada."
        )
    else 
        echo >&2 "Já havia a instância-$INSTANCIA_ID na conta em execução."
    fi
    echo "$INSTANCIA_ID"
}

alocarIpElastico(){
    local instancia="$1"
    local posicao="$2"
    local ip=$(aws ec2 describe-addresses \
        --query "Addresses[?InstanceId=='$instancia'].PublicIp" \
        --output text)
    
    if [ -n "$ip" ]; then
        echo >&2 "A instância $instancia já possui IP elástico."
        echo "$ip"
    else
        local EIP=$(aws ec2 describe-addresses --query "Addresses[?AssociationId==null].PublicIp | [$2]" --output text)
        if [ $? -eq 0 ]; then
            aws ec2 associate-address \
                --instance-id "$instancia" \
                --public-ip "$EIP" \
                --query 'AssociationId' \
                --output text > /dev/null 2>&1
                echo >&2 "Foi associado a instância um IP elático disponível na conta."
        else
            local EIP=$(aws ec2 allocate-address \
                --domain vpc \
                --query 'PublicIp' \
                --output text)
            
            aws ec2 associate-address \
                --instance-id "$instancia" \
                --public-ip "$EIP" \
                --query 'AssociationId' \
                --output text > /dev/null 2>&1
                echo >&2 "Um novo IP elático elástico foi criado e associado a instância."
            
        fi
        echo "$EIP"
    fi
}

criarBucket(){
    local nome="$1"
    if ! aws s3api list-buckets --query "Buckets[].Name" --output text | tr '\t' '\n' | grep -q "^$nome"; then
        while true; do
            bucket_name="$nome-$(date +%s)"
            aws s3 mb s3://$bucket_name > /dev/null 2>&1
            if [ $? -eq 0 ]; then
            echo >&2 "Bucket "$nome" criado."
                break
            else
                sleep 1
            fi
        done
    else
        echo >&2 "Já havia o bucket "$nome"."
    fi
}

mkdir tmp

criarScriptDeInicializacao

TEMP_FILE_DB="./tmp/ID_DB.txt"
TEMP_FILE_WEB="./tmp/ID_WEB.txt"
TEMP_FILE_JAVA="./tmp/ID_JAVA.txt"

trap 'rm -f tmp; echo "Arquivos temporários apagados."' EXIT

VPC_ID=$(escolherVPC 0)
(
    definirParDeChaves "ChaveInstanciaDB" "instancia-db" 
    SG_ID_DB=$(criarGrupoDeSeguranca "GrupoSegurancaDB" "Grupo-de-seguranca-db" "$VPC_ID" "db")
    adicionarRegraAoGrupo "$SG_ID_DB" 3306
    adicionarRegraAoGrupo "$SG_ID_DB" 22
    ID_DB=$(criarInstancia "db" "ChaveInstanciaDB" "ami-0360c520857e3138f" "t3.small" $SG_ID_DB)
    echo "$ID_DB" > "$TEMP_FILE_DB"
) &
(
    definirParDeChaves "ChaveInstanciaWEB" "instancia-web" 
    SG_ID_WEB=$(criarGrupoDeSeguranca "GrupoSegurancaWEB" "Grupo-de-seguranca-web" "$VPC_ID" "web")
    adicionarRegraAoGrupo "$SG_ID_WEB" 80
    adicionarRegraAoGrupo "$SG_ID_WEB" 22
    ID_WEB=$(criarInstancia "web" "ChaveInstanciaWEB" "ami-0360c520857e3138f" "t3.small" $SG_ID_WEB)
    echo "$ID_WEB" > "$TEMP_FILE_WEB"
) & 
(
    definirParDeChaves "ChaveInstanciaJAVA" "instancia-java" 
    SG_ID_JAVA=$(criarGrupoDeSeguranca "GrupoSegurancaJAVA" "Grupo-de-seguranca-java" "$VPC_ID" "jar")
    adicionarRegraAoGrupo "$SG_ID_JAVA" 22
    ID_JAVA=$(criarInstancia "java" "ChaveInstanciaJAVA" "ami-0360c520857e3138f" "t3.small" $SG_ID_JAVA)
    echo "$ID_JAVA" > "$TEMP_FILE_JAVA"
) & 
(
    criarBucket "black-screen-raw"
) & 
(
    criarBucket "black-screen-trusted"
) &
(
    criarBucket "black-screen-client"
) & wait

ID_DB=$(cat "$TEMP_FILE_DB")
ID_WEB=$(cat "$TEMP_FILE_WEB")
ID_JAVA=$(cat "$TEMP_FILE_JAVA")

(
    aws ec2 wait instance-running --instance-ids $ID_WEB
    IP_WEB=$(alocarIpElastico $ID_WEB 0)
) &
(
    aws ec2 wait instance-running --instance-ids $ID_JAVA
    IP_JAVA=$(alocarIpElastico $ID_JAVA 1)
) &
(
    aws ec2 wait instance-running --instance-ids $ID_DB
    IP_DB=$(alocarIpElastico $ID_DB 2)
) & wait

