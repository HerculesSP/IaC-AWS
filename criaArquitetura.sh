#!/bin/bash

escolherVPC(){
    local vpc_id=$(aws ec2 describe-vpcs \
        --query "Vpcs[$1].VpcId" \
        --output text)
    echo >&2 "VPC encontrada"
    echo "$vpc_id"
}

escolherSubNet(){
    local subnet_id=$(aws ec2 describe-subnets \
        --query "Subnets[?VpcId=='$VPC_ID'].[SubnetId]" \
        --output text | head -n1)
    echo >&2 "Subrede encontrada"
    echo "$subnet_id"
}

definirParDeChaves(){
    aws ec2 describe-key-pairs --key-names "$1" --query "KeyPairs[0].KeyName" --output text > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        if [ ! -f "$1.pem" ]; then
            aws ec2 delete-key-pair --key-name "$1" --output text > /dev/null 2>&1
            echo >&2 "Par de chaves "$1" apagado, pois não se encontra no diretório"
            local APAGAR=$(aws ec2 describe-instances \
                --filters "Name=tag:Name,Values=$2" \
                    "Name=key-name,Values=$1" \
                    "Name=instance-state-name,Values=running" \
                --query "Reservations[].Instances[0].InstanceId" \
                --output text)
            if [ $? -eq 0 ]; then
                aws ec2 terminate-instances --instance-ids "$APAGAR" --output text > /dev/null 2>&1
                echo >&2 "Instância associada ao par de chaves excluido foi apagada"
                sleep 15
            fi

            aws ec2 create-key-pair \
            --key-name "$1" \
            --region us-east-1 \
            --query 'KeyMaterial' \
            --output text > "$1.pem"
            echo >&2 "Novo par de chaves "$1" criado"
        else 
            echo >&2 "Par de chaves "$1" já se encontra criado"
        fi
    else
        rm -f "$1.pem"
        aws ec2 create-key-pair \
        --key-name "$1" \
        --region us-east-1 \
        --query 'KeyMaterial' \
        --output text > "$1.pem"
        echo >&2 "Novo par de chaves "$1" criado"
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
    local protocolo="$3" 
    local ip="$4"

    local regra_existente=$(aws ec2 describe-security-group-rules \
    --filters Name="group-id",Values="$sg_id" \
    --query "SecurityGroupRules[?FromPort == \`${porta}\` && ToPort == \`${porta}\` && CidrIpv4 == \`$ip\`]" \
    --output text)

    if [ -z "$regra_existente" ] || [ "$regra_existente" = "None" ]; then
        echo "Adicionando regra de entrada: porta $porta para o IP $ip"
        aws ec2 authorize-security-group-ingress \
            --group-id "$sg_id" \
            --ip-permissions "[
                {
                    \"IpProtocol\": \"$protocolo\",
                    \"FromPort\": $porta,
                    \"ToPort\": $porta,
                    \"IpRanges\": [{\"CidrIp\": \"$ip\"}]
                }
            ]" \
            --output text > /dev/null 2>&1
    else
        echo "Regra de porta $porta no IP $ip já existe no grupo $sg_id"
    fi
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

    aws ec2 wait instance-running --instance-ids $instancia
    local ip=$(aws ec2 describe-addresses \
        --query "Addresses[?InstanceId=='$instancia'].PublicIp" \
        --output text)
    
    if [ -n "$ip" ]; then
        echo >&2 "A instância $instancia já possui IP elástico."
        echo "$ip"
    else
        local EIP=$(aws ec2 describe-addresses --query "Addresses[?AssociationId==null].PublicIp | [$posicao]" --output text)
        if [ -n "$EIP" ] && [ "$EIP" != "None" ]; then
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
    
    local full_name=$(aws s3api list-buckets --query "Buckets[].Name" --output text | tr '\t' '\n' | grep "^$nome-[0-9]\{10\}" | head -n 1)
    if [ -n "$full_name" ]; then
        echo >&2 "Já havia o bucket \"$full_name\"."
        echo "$full_name"
        return
    fi
    while true; do
        full_name="$nome-$(date +%s)"
        aws s3 mb s3://$full_name > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo >&2 "Bucket \"$full_name\" criado."
            break
        else
            sleep 1
        fi
    done

    echo "$full_name"
}



STARTTIME=$(date +%s)

mkdir tmp

TEMP_FILE_ID_DB="./tmp/ID_DB.txt"
TEMP_FILE_ID_WEB="./tmp/ID_WEB.txt"
TEMP_FILE_ID_JAVA="./tmp/ID_JAVA.txt"
TEMP_FILE_SG_DB="./tmp/SG_DB.txt"
TEMP_FILE_IP_DB="./tmp/IP_DB.txt"
TEMP_FILE_IP_WEB="./tmp/IP_WEB.txt"
TEMP_FILE_IP_JAVA="./tmp/IP_JAVA.txt"
TEMP_FILE_RAW="./tmp/RAW.txt"
TEMP_FILE_TRUSTED="./tmp/TRUSTED.txt"
TEMP_FILE_CLIENT="./tmp/CLIENT.txt"

trap 'rm -r -f tmp; echo "Arquivos temporários apagados."' EXIT

VPC_ID=$(escolherVPC 0)
(
    definirParDeChaves "ChaveInstanciaDB" "instancia-db" 
    SG_ID_DB=$(criarGrupoDeSeguranca "GrupoSegurancaDB" "Grupo-de-seguranca-db" "$VPC_ID" "db")
    adicionarRegraAoGrupo "$SG_ID_DB" 22 "tcp" "0.0.0.0/0"
    ID_DB=$(criarInstancia "db" "ChaveInstanciaDB" "ami-0360c520857e3138f" "t3.small" $SG_ID_DB)
    echo "$ID_DB" > "$TEMP_FILE_ID_DB"
    echo "$SG_ID_DB" > "$TEMP_FILE_SG_DB"
) &
(
    definirParDeChaves "ChaveInstanciaWEB" "instancia-web" 
    SG_ID_WEB=$(criarGrupoDeSeguranca "GrupoSegurancaWEB" "Grupo-de-seguranca-web" "$VPC_ID" "web")
    adicionarRegraAoGrupo "$SG_ID_WEB" 22 "tcp" "0.0.0.0/0"
    adicionarRegraAoGrupo "$SG_ID_WEB" 80 "tcp" "0.0.0.0/0"
    ID_WEB=$(criarInstancia "web" "ChaveInstanciaWEB" "ami-0360c520857e3138f" "t3.small" $SG_ID_WEB)
    echo "$ID_WEB" > "$TEMP_FILE_ID_WEB"
) & 
(
    definirParDeChaves "ChaveInstanciaJAVA" "instancia-java" 
    SG_ID_JAVA=$(criarGrupoDeSeguranca "GrupoSegurancaJAVA" "Grupo-de-seguranca-java" "$VPC_ID" "jar")
    adicionarRegraAoGrupo "$SG_ID_JAVA" 22 "tcp" "0.0.0.0/0"
    ID_JAVA=$(criarInstancia "java" "ChaveInstanciaJAVA" "ami-0360c520857e3138f" "t3.small" $SG_ID_JAVA)
    echo "$ID_JAVA" > "$TEMP_FILE_ID_JAVA"
) & 
(
    RAW=$(criarBucket "black-screen-raw")
    echo "$RAW" > "$TEMP_FILE_RAW"
) & 
(
    TRUSTED=$(criarBucket "black-screen-trusted")
    echo "$TRUSTED" > "$TEMP_FILE_TRUSTED"
) &
(
    CLIENT=$(criarBucket "black-screen-client")
    echo "$CLIENT" > "$TEMP_FILE_CLIENT"
) & wait

ID_DB=$(cat "$TEMP_FILE_ID_DB")
ID_WEB=$(cat "$TEMP_FILE_ID_WEB")
ID_JAVA=$(cat "$TEMP_FILE_ID_JAVA")
SG_DB=$(cat "$TEMP_FILE_SG_DB")
RAW=$(cat "$TEMP_FILE_RAW")
TRUSTED=$(cat "$TEMP_FILE_TRUSTED")
CLIENT=$(cat "$TEMP_FILE_CLIENT")

(
    sleep 0.1
    IP_WEB=$(alocarIpElastico $ID_WEB 0)
    echo "$IP_WEB" > "$TEMP_FILE_IP_WEB"
) &
(
    sleep 0.3
    IP_JAVA=$(alocarIpElastico $ID_JAVA 1)
    echo "$IP_JAVA" > "$TEMP_FILE_IP_JAVA"
) &
(   sleep 0.5
    IP_DB=$(alocarIpElastico $ID_DB 0)
    echo "$IP_DB" > "$TEMP_FILE_IP_DB"
) & wait

IP_DB=$(cat "$TEMP_FILE_IP_DB")
IP_WEB=$(cat "$TEMP_FILE_IP_WEB")
IP_JAVA=$(cat "$TEMP_FILE_IP_JAVA")

(
    adicionarRegraAoGrupo "$SG_DB" 3306 "tcp" "${IP_WEB}/32"
) &
(
    adicionarRegraAoGrupo "$SG_DB" 3306 "tcp" "${IP_JAVA}/32"
) & wait

(
    AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id --profile default)
    AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key --profile default)
    AWS_SESSION_TOKEN=$(aws configure get aws_session_token --profile default)

    echo "Configurando o ambiente da instância WEB"
    #ssh -i ChaveInstanciaWEB.pem -o StrictHostKeyChecking=no ubuntu@$IP_WEB 'bash -s' -- $IP_DB $AWS_ACCESS_KEY_ID $AWS_SECRET_ACCESS_KEY $AWS_SESSION_TOKEN $RAW < ./scriptsConfiguracao/inicializacaoWEB.sh
) &
(
    echo "Configurando o ambiente da instância JAVA"
    #ssh -i ChaveInstanciaJAVA.pem -o StrictHostKeyChecking=no ubuntu@$IP_JAVA 'bash -s' -- $IP_DB < ./scriptsConfiguracao/inicializacaoJAVA.sh
) &
(
   echo "Configurando o ambiente da instância DB"
   ssh -i ChaveInstanciaDB.pem -o StrictHostKeyChecking=no ubuntu@$IP_DB 'bash -s' < ./scriptsConfiguracao/inicializacaoDB.sh
) & wait
ENDTIME=$(date +%s)
echo "O script levou $(($ENDTIME - $STARTTIME)) segundos para ser concluído."
