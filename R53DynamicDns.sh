#!/bin/bash

# Updates A and/or AAAA records on Route 53 with your dynamic IPv4/IPv6 Address
# Keith Vassallo <keith@vassallo.cloud>
# GitHub: https://github.com/keithvassallomt/r53dynamicdns
# Based on: https://gist.github.com/chetan/aac5f03c9ad6a0772ce4 by @chetan

# Usage:
# 1. Update records.json with the records you want to update.
# 2. Change the two variables below, if necessary.
# 3. Make sure this script is executable: chmod +x R53DynamicDns.sh.
# 4. Run it.
# 5. Profit.

PROFILE=""  # A profile to use for awscli
COMMENT="Auto updating @ `date`"  # The comment to append to the update operation

# That's it! No need to modify anything below this line ------------------------------------------------------------

# https://stackoverflow.com/questions/13777387/check-for-ip-validity
function valid_ip4() {
  local ip=${1:-NO_IP_PROVIDED}
  local IFS=.; local -a a=($ip)
  # Start with a regex format test
  [[ $ip =~ ^[0-9]+(\.[0-9]+){3}$ ]] || return 1
  # Test values of quads
  local quad
  for quad in {0..3}; do
    [[ "${a[$quad]}" -gt 255 ]] && return 1
  done
  return 0
}

function valid_ip6()
{
    local ipv6="$1"
    
    # Regular expression for a valid IPv6 address
    local ipv6_regex="^([0-9a-fA-F]{1,4}:){7}([0-9a-fA-F]{1,4}|:)$|^([0-9a-fA-F]{1,4}:){1,7}:$|^([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}$|^([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}$|^([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}$|^([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}$|^([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}$|^[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})$|^:((:[0-9a-fA-F]{1,4}){1,7}|:)$|^fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}$|^::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]|)[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]|)[0-9])$|^([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]|)[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]|)[0-9])$"

    if [[ $ipv6 =~ $ipv6_regex ]]; then
        return 0
    else
        return 1
    fi
}

# Get current directory
# (from http://stackoverflow.com/a/246128/920350)
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOGFILE="$DIR/R53DynamicDns.log"

echo "R53DynamicDns Started on $(date)" >> $LOGFILE

# Set the profile flag if used
PROFILEFLAG=""
if [ -n "$PROFILE" ]; then
    PROFILEFLAG="--profile $PROFILE"
fi

# Get the external IP addresses 
IP4=`curl --silent ip4only.me/api/ | cut -d ',' -f2`
IP6=`curl --silent ip6only.me/api/ | cut -d ',' -f2`

echo "Public IPv4 address detected as $IP4" >> $LOGFILE
echo "Public IPv6 address detected as $IP6" >> $LOGFILE

# Validate the IP addresses
process_ip4=true
if ! valid_ip4 $IP4; then
    echo "Invalid IPv4 address: $IP4 - IPv4 updates will be skipped" >> "$LOGFILE"
    process_ip4=false
fi
process_ip6=true
if ! valid_ip6 $IP6; then
    echo "Invalid IPv6 address: $IP6 - IPv6 updates will be skipped" >> "$LOGFILE"
    process_ip6=false
fi

# Check current IPv4 against cache file
IP4FILE="$DIR/R53DynamicDns_cache.ip4"
if [ ! -f "$IP4FILE" ]
    then
    echo "$IP4" > "$IP4FILE"
else
    cached_ip4=`cat $IP4FILE`
    if [[ $process_ip4 && $IP4 = $cached_ip4 ]]
    then
        echo "Your local IPv4 address has not changed since last run. Skipping IPv4 updates." >> $LOGFILE
        process_ip4=false
    fi
fi

# Check current IPv6 against cache file
IP6FILE="$DIR/R53DynamicDns_cache.ip6"
if [ ! -f "$IP6FILE" ]
    then
    echo "$IP6" > "$IP6FILE"
else
    cached_ip6=`cat $IP6FILE`
    if [[ $process_ip6 && $IP6 = $cached_ip6 ]]
    then
        echo "Your local IPv6 address has not changed since last run. Skipping IPv6 updates." >> $LOGFILE
        process_ip6=false
    fi
fi

if [[ "$process_ip4" == "false" && "$process_ip6" == "false" ]]; then
    echo "Both your IPv4 and IPv6 addresses have not changed since last run. Exiting." >> $LOGFILE
    echo "------------------------------------------------------------" >> $LOGFILE
    exit 0
fi


jq -c '.[]' records.json | while read record; do
    # Extract JSON record
    r_name=`jq -r '.name' <<< $record`
    r_zone=`jq -r '.zone' <<< $record`
    r_ttl=`jq '.ttl' <<< $record`
    r_ip4=`jq '.ip4' <<< $record`
    r_ip6=`jq '.ip6' <<< $record`

    echo "Now processing record: $r_name" >> $LOGFILE

    # Process IPv4 Record
    if [[ "$r_ip4" == "true" && "$process_ip4" == "true" ]] ; then
        # Get the current IPv4 address on AWS
        aws_ip4="$(
        aws $PROFILEFLAG route53 list-resource-record-sets \
            --hosted-zone-id "$r_zone" --start-record-name "$r_name" \
            --start-record-type A --max-items 1 \
            --output json | jq -r \ '.ResourceRecordSets[].ResourceRecords[].Value'
        )"
        echo "Current IPv4 Address in AWS is $aws_ip4" >> $LOGFILE

        if [ "$IP4" ==  "$aws_ip4" ]; then
            echo "IPv4 is still $IP4. No update needed" >> $LOGFILE
        else
            # Update IPv4
            TMPFILE=$(mktemp /tmp/temporary-file.XXXXXXXX)
            cat > ${TMPFILE} << EOF
            {
                "Comment":"$COMMENT",
                "Changes":[
                    {
                        "Action":"UPSERT",
                        "ResourceRecordSet":{
                            "ResourceRecords":[
                                {
                                    "Value":"$IP4"
                                }
                            ],
                            "Name":"$r_name",
                            "Type":"A",
                            "TTL":$r_ttl
                        }
                    }
                ]
            }
EOF

            aws $PROFILEFLAG route53 change-resource-record-sets \
            --hosted-zone-id $r_zone \
            --change-batch file://"$TMPFILE" \
            --query '[ChangeInfo.Comment, ChangeInfo.Id, ChangeInfo.Status, ChangeInfo.SubmittedAt]' \
            --output text >> "$LOGFILE"
            echo "" >> "$LOGFILE"
            rm $TMPFILE
        fi
    fi

    # Process IPv6 Record
    if [[ "$r_ip6" == "true" && "$process_ip6" == "true" ]] ; then
        # Get the current IPv6 address on AWS
        aws_ip6="$(
        aws $PROFILEFLAG route53 list-resource-record-sets \
            --hosted-zone-id "$r_zone" --start-record-name "$r_name" \
            --start-record-type AAAA --max-items 1 \
            --output json | jq -r \ '.ResourceRecordSets[].ResourceRecords[].Value'
        )"
        echo "Current IPv6 Address in AWS is $aws_ip6" >> $LOGFILE

        if [ "$IP6" ==  "$aws_ip6" ]; then
            echo "IPv6 is still $IP6. No update needed" >> $LOGFILE
        else
            # Update IPv6
            TMPFILE=$(mktemp /tmp/temporary-file.XXXXXXXX)
            cat > ${TMPFILE} << EOF
            {
                "Comment":"$COMMENT",
                "Changes":[
                    {
                        "Action":"UPSERT",
                        "ResourceRecordSet":{
                            "ResourceRecords":[
                                {
                                    "Value":"$IP6"
                                }
                            ],
                            "Name":"$r_name",
                            "Type":"AAAA",
                            "TTL":$r_ttl
                        }
                    }
                ]
            }
EOF

            aws $PROFILEFLAG route53 change-resource-record-sets \
            --hosted-zone-id $r_zone \
            --change-batch file://"$TMPFILE" \
            --query '[ChangeInfo.Comment, ChangeInfo.Id, ChangeInfo.Status, ChangeInfo.SubmittedAt]' \
            --output text >> "$LOGFILE"
            echo "" >> "$LOGFILE"
            rm $TMPFILE
        fi
    fi
done


echo "------------------------------------------------------------" >> $LOGFILE
