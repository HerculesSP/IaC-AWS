#!/bin/bash
echo "ALERTA: Diversos erros podem aparecer no terminal, ignore-os."
criarBucket(){
    if ! aws s3api list-buckets --query "Buckets[].Name" --output text | tr '\t' '\n' | grep -q "^$1"; then
        while true; do
            bucket_name="${1}-$(date +%s)"
            aws s3 mb s3://$bucket_name
            if [ $? -eq 0 ]; then
                break
            else
                sleep 1
            fi
        done
    fi
}

criarBucket "black-screen-raw"

