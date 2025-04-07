#!/bin/bash
###########################################################
#KR  10.234.0.0/24 
#
CLIENTIPSTART="10.234.107.1"
CLIENTIPQTY=4
#CLIENTIPSTART_FROM_OPENVPN
#CLIENTIPQTY_FROM_OPENVPN

export CLIENTIPQTY  
#IPROUTETYPE SINGLE/PREFIX
IPROUTETYPE="PREFIX"

exiterr()  { echo "Error: $1" >&2; exit 1; }
conf_bk() { /bin/cp -f "$1" "$1.old-$SYS_DT" 2>/dev/null; }

check_ip() {
    IP_REGEX='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$'
    printf '%s' "$1" | tr -d '\n' | grep -Eq "$IP_REGEX"
}

check_pvt_ip() {
    IPP_REGEX='^(10|127|172\.(1[6-9]|2[0-9]|3[0-1])|192\.168|169\.254)\.'
    printf '%s' "$1" | tr -d '\n' | grep -Eq "$IPP_REGEX"
}


checkexport() {
    if env | grep -q "^CLIENTIPQTY="; then
        echo "CLIENTIPQTY" $CLIENTIPQTY
    else
        CLIENTIPQTY=1
        echo "CLIENTIPQTY not exists.Now set CLIENTIPQTY to 1"
    fi
    if ! check_pvt_ip "$CLIENTIPSTART"; then
        exiterr "CLIENTIPSTART not exists"
    fi
    if (( CLIENTIPQTY == 1 )); then
        IPROUTETYPE="SINGLE"
    fi
}


increment_ip() {
    local ip=$1
    local increment=$2
    local IFS=.
    local new_ip
 
    # 将 IP 地址分割为数组
    read -ra ip_parts <<< "$ip"
 
    # 计算新的 IP 地址的每一部分
    for (( i=3; i>=0; i-- )); do
        # 对每个部分进行加法运算，并考虑进位
        new_ip_part=$((10#${ip_parts[i]} + increment))
        ip_parts[i]=$((new_ip_part % 256))  # 取余数确保不会超过255
        increment=$((new_ip_part / 256))   # 计算进位值
    done
 
    # 重新组合新的 IP 地址
    new_ip="${ip_parts[0]}.${ip_parts[1]}.${ip_parts[2]}.${ip_parts[3]}"
    echo "$new_ip"
}


generateinterface() {
    local IFS=.
 
    # 将 IP 地址分割为数组
    read -ra ip_parts <<< "$CLIENTIPSTART"
    interefaceID="${ip_parts[2]}"
    CLIENTPREFIX="${ip_parts[0]}.${ip_parts[1]}.${ip_parts[2]}.0/24"
}

file="sokan.ovpn"

check_file_exists() {
if [ -f "$1" ]; then
    echo "File $1 is Okay"
    file="$1"
else
    if [ -f "$file" ]; then
        echo "File $file is Okay"
    else
        exiterr "file not exists"
    fi
fi

    if ! check_ip "$gCLIENTIPSTART"; then
        get_public_ip=$(grep -m 1 -oE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' <<< "$(wget -T 10 -t 1 -4qO- "$ip_url2" || curl -m 10 -4Ls "$ip_url2")")
    fi

}


analyseovpn() {
content=""
 
while IFS= read -r line; do
    content+="$line"
    substr="proto "
    if echo "$line" | grep -q "$substr"; then
        protocol=$(echo $line | awk '{print $2}')
        echo "protocol" $protocol
    fi
    substr="remote "
    if echo "$line" | grep -q "$substr"; then
        remotehost=$(echo $line | awk '{print $2}')
        remoteport=$(echo $line | awk '{print $3}')
        echo "remotehost" $remotehost
        echo "remoteport" $remoteport
    fi
done < "$file"
 
#echo "$content"   
}
 


getpkica() {
start_str="<ca>-----BEGIN CERTIFICATE-----"
end_str="-----END CERTIFICATE-----"
pkica=$(echo $content | grep -o -P "(?<=${start_str}).*?(?=${end_str})")

start_str="<cert>-----BEGIN CERTIFICATE-----"
end_str="-----END CERTIFICATE-----"
pkicert=$(echo $content | grep -o -P "(?<=${start_str}).*?(?=${end_str})")

start_str="<key>-----BEGIN PRIVATE KEY-----"
end_str="-----END PRIVATE KEY-----"
pkikey=$(echo $content | grep -o -P "(?<=${start_str}).*?(?=${end_str})")

start_str="<tls-crypt>-----BEGIN OpenVPN Static key V1-----"
end_str="-----END OpenVPN Static key V1-----"
pkicyrpt=$(echo $content | grep -o -P "(?<=${start_str}).*?(?=${end_str})")


#echo "$pkica" 
#echo "$pkicert" 
#echo "$pkikey" 
#echo "$pkicyrpt" 

}

generateconf() {
    vyosresult="\n\n\n*************vyos openvpn client config \n"

    script="set pki ca ca-${interefaceID} certificate '${pkica}'\n"
    vyosresult="${vyosresult}\n${script}"

    script="set pki certificate client-${interefaceID} certificate '${pkicert}'\n"
    vyosresult="${vyosresult}\n${script}"

    script="set pki certificate client-${interefaceID} private key '${pkikey}'\n"
    vyosresult="${vyosresult}\n${script}"

    script="set pki openvpn shared-secret client-${interefaceID} key '${pkicyrpt}'\n"
    vyosresult="${vyosresult}\n${script}"

    script="set interfaces openvpn vtun${interefaceID} encryption data-ciphers aes256gcm"
    vyosresult="${vyosresult}\n${script}"

    script="set interfaces openvpn vtun${interefaceID} hash sha256"
    vyosresult="${vyosresult}\n${script}"

    script="set interfaces openvpn vtun${interefaceID} mode client"
    vyosresult="${vyosresult}\n${script}"

    script="set interfaces openvpn vtun${interefaceID} persistent-tunnel"
    vyosresult="${vyosresult}\n${script}"

    script="set interfaces openvpn vtun${interefaceID} openvpn-option 'remote-cert-tls server'"
    vyosresult="${vyosresult}\n${script}"

    script="set interfaces openvpn vtun${interefaceID} openvpn-option 'tls-version-min 1.2'"
    vyosresult="${vyosresult}\n${script}"

    script="set interfaces openvpn vtun${interefaceID} protocol tcp-active"
    vyosresult="${vyosresult}\n${script}"

    script="set interfaces openvpn vtun${interefaceID} remote-host ${remotehost}"
    vyosresult="${vyosresult}\n${script}"

    script="set interfaces openvpn vtun${interefaceID} remote-port ${remoteport}"
    vyosresult="${vyosresult}\n${script}"

    script="set interfaces openvpn vtun${interefaceID} tls  ca-certificate ca-${interefaceID}"
    vyosresult="${vyosresult}\n${script}"

    script="set interfaces openvpn vtun${interefaceID} tls  certificate client-${interefaceID} "
    vyosresult="${vyosresult}\n${script}"

    script="set interfaces openvpn vtun${interefaceID} tls  crypt-key client-${interefaceID} "
    vyosresult="${vyosresult}\n${script}"

}

generateroure() {
    
    script="set policy local-route rule  ${interefaceID} set table  ${interefaceID}"
    vyosresult="${vyosresult}\n${script}"

    script="set protocol static table  ${interefaceID} route 0.0.0.0/0 interface vtun${interefaceID} "
    vyosresult="${vyosresult}\n${script}"

    if [ "$IPROUTETYPE" = "PREFIX" ]; then
        script="set policy local-route rule  ${interefaceID} source address  ${CLIENTPREFIX}"
        vyosresult="${vyosresult}\n${script}"        
    else
        count=1
        while [ $count -le $CLIENTIPQTY ]; do
            script="set policy local-route rule  ${interefaceID} source address  ${CLIENTIPSTART}"
            vyosresult="${vyosresult}\n${script}"  
            CLIENTIPSTART=$(increment_ip "$CLIENTIPSTART" "1")
       
          echo "计数: $count"
          ((count++))
        done
    fi
    echo -e $vyosresult
}

  
generatedeleteconf() {

    vyosdelete="\n\n\n*************vyos delete config \n"

    script="delete policy local-route rule  ${interefaceID} "
    vyosdelete="${vyosdelete}\n${script}"

    script="delete protocol static table  ${interefaceID}  "
    vyosdelete="${vyosdelete}\n${script}"

    script="delete interfaces openvpn vtun${interefaceID} \n"
    vyosdelete="${vyosdelete}\n${script}"

    script="delete pki ca ca-${interefaceID}\n"
    vyosdelete="${vyosdelete}\n${script}"

    script="delete pki certificate client-${interefaceID}\n"
    vyosdelete="${vyosdelete}\n${script}"

    script="delete pki openvpn shared-secret client-${interefaceID}\n"
    vyosdelete="${vyosdelete}\n${script}"

    echo -e $vyosdelete
}


shellexecute() {
    checkexport
    check_file_exists "$@"
    analyseovpn
    getpkica
    generateinterface
    generateconf
    generateroure
    generatedeleteconf

}

shellexecute "$@"

