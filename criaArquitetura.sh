echo "ALERTA: Diversos erros podem aparecer no terminal, ignore-os."

escolherVPC(){
    local vpc_id=$(aws ec2 describe-vpcs \
        --query "Vpcs[$1].VpcId" \
        --output text)
    echo "$vpc_id"
}