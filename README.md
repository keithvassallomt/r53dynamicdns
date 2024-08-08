# R53DyamicDns

## What is it?
This is a simple script to update A and AAAA records in AWS Route53 when you have a dynamic IP address. 

Based on the [gist](https://gist.github.com/chetan/aac5f03c9ad6a0772ce4) by [@chetan](https://gist.github.com/chetan).

When your local IPs have not changed, or when the remote records are the same as the local IPs, the script does not perform any updates.

## Usage

1. Fill in the records you want to update in `records.json.sample`. Fields are as follows:
- `name` - the recordset you want to update.
- `zone` - your AWS zone id.
- `ttl` - the TTL value.
- `ip4` - boolean. Whether you want to update the `A` record with your IPv4 address.
- `ip6` - boolean. Whether you want to update the `AAAA` record with your IPv6 address.

2. Rename `records.json.sample` to `records.json`.

3. If necessary, modify `R53DynamicDns.sh` and add your AWS CLI profile name to the `PROFILE` variable. You'll need to do this if you have multiple AWS CLI profiles configured and the one you want to use for DNS updates is not the default profile. 

3. Make the script executable:
    ```bash
    chmod +x R53DynamicDns.sh
    ```

4. Run it.
    ```bash
    ./R53DynamicDns.sh
    ```

5. Optional. Add an entry in `/etc/crontab` to run this every hour. Replace `user` with your username and specify the correct path.
    ```bash
    echo '*/59 * * * *    user   /path/to/R53DynamicDns.sh' > /etc/crontab
    ```

## Requirements

This script requires:

- [jq](https://jqlang.github.io/jq/).
- The [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).