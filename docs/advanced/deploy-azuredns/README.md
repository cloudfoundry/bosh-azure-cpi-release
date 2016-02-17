# Deploy Azure DNS

Domains in Cloud Foundry provide a namespace from which to create routes. The presence of a domain in Cloud Foundry indicates to a developer that requests for any route created from the domain will be routed to Cloud Foundry. Cloud Foundry supports two domains, one is called SYSTEM-DOMAIN for system applications and one for general applications. To deploy Cloud Foundry, you need to specify the SYSTEM-DOMAIN in the manifest, and it should be resolvable.

There are several ways to setup DNS.

* [xip.io](http://xip.io/) is a magic domain name that provides wildcard DNS for any IP address. By default, the setction `get-started` in our guidance use xip.io to resolve the system domain.
* **Azure DNS**
* Buy 3-party DNS service
* Use open source softwares (e.g. `bind9`)

If your deployment is for production environment, we recommend [Azure DNS](https://azure.microsoft.com/en-us/services/dns/) to you.

There are two steps to host your domain in Azure. The first step is to create Azure DNS service, and the second step is to register Azure DNS in your domain name service provider.

## 1 Create Azure DNS

### 1.1 via the ARM template

You can deploy the template [azuredns.json](./azuredns.json). By default, it will manage a DNS zone which you provides, and resolve `*.<system-domain>` to your Cloud Foundry public IP.

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fcloudfoundry-incubator%2Fbosh-azure-cpi-release%2Fmaster%2Fdocs%Fadvanced%Fdeploy-azuredns%2Fazuredns.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>

| Name | Required | Description |
|:----:|:--------:|:----------- |
| systemDomainName | **YES** | Name of System Domain |
| cloudFoundryIPAddress | **YES** | The public IP address of Cloud Foundry |

You can put your own domain name as `systemDomainName`, and get `cloudFoundryIPAddress` with the command `cat ~/settings | grep cf-ip`.

For example: The deployment will create a DNS Record Set "*" of type "A" for the system domain `microsoftlovelinux.com`, and map it to the public IP address of Cloud Foundry `123.123.123.123`. 

```
info:    Executing command network dns record-set show
Type: A
+ Looking up the DNS Record Set "*" of type "A"
data:    Id                              : /subscriptions/########-####-####-####-############/resourceGroups/cf734feb24918045a7aa6527/providers/Microsoft.Network/dnszones/microsoftlovelinux.com/A/*
data:    Name                            : *
data:    Type                            : Microsoft.Network/dnszones/A
data:    Location                        : global
data:    TTL                             : 3600
data:    A records:
data:        IPv4 address                : 123.123.123.123
data:
info:    network dns record-set show command OK
```

### 1.2 Manually

You can also use Azure CLI to manage DNS zones and records manually.

1. Create a DNS zone

  ```
  azure network dns zone create --resource-group <resource-group> --name <name>
  ```

  Example:

  ```
  $ azure network dns zone create --resource-group cfc6f8ef9cabd8490687806b --name mslinux.love
  info:    Executing command network dns zone create
  + Creating dns zone "mslinux.love"
  + Looking up the dns zone "mslinux.love"
  data:    Id                              : /subscriptions/########-####-####-####-############/resourceGroups/cfc6f8ef9cabd8490687806b/providers/Microsoft.Network/dnszones/mslinux.love
  data:    Name                            : mslinux.love
  data:    Type                            : Microsoft.Network/dnszones
  data:    Location                        : global
  data:    Number of record sets           : 2
  data:    Max number of record sets       : 1000
  info:    network dns zone create command OK
  ```

2. Create DNS records

  1. Create a record set

    ```
    azure network dns record-set create --resource-group <resource-group> --dns-zone-name <dns-zone-name> --name <name> --type <type> --ttl <ttl>
    ```

    Example:

    ```
    $ azure network dns record-set create --resource-group cfc6f8ef9cabd8490687806b --dns-zone-name mslinux.love --name "*" --type A --ttl 3600
    info:    Executing command network dns record-set create
    + Creating DNS record set "*"
    data:    Id                              : /subscriptions/########-####-####-####-############/resourceGroups/cfc6f8ef9cabd8490687806b/providers/Microsoft.Network/dnszones/mslinux.love/A/*
    data:    Name                            : *
    data:    Type                            : Microsoft.Network/dnszones/A
    data:    Location                        : global
    data:    TTL                             : 3600
    info:    network dns record-set create command OK
    ```

  2. Add a record into the resord set

  ```
  azure network dns record-set add-record --resource-group <resource-group> --dns-zone-name <dns-zone-name> --record-set-name <record-set-name> --type <type> --ipv4-address <ipv4-address>
  ```

  Example:

  ```
  $ azure network dns record-set add-record --resource-group cfc6f8ef9cabd8490687806b --dns-zone-name mslinux.love --record-set-name "*" --type A --ipv4-address "123.123.123.123"
  info:    Executing command network dns record-set add-record
  + Looking up the dns zone "mslinux.love"
  + Looking up the DNS Record Set "*" of type "A"
  + Updating record set "*"
  data:    Id                              : /subscriptions/########-####-####-####-############/resourceGroups/cfc6f8ef9cabd8490687806b/providers/Microsoft.Network/dnszones/mslinux.love/A/*
  data:    Name                            : *
  data:    Type                            : Microsoft.Network/dnszones/A
  data:    Location                        : global
  data:    TTL                             : 3600
  data:    A records:
  data:        IPv4 address                : 123.123.123.123
  data:
  info:    network dns record-set add-record command OK
  ```

Please click [**HERE**](https://azure.microsoft.com/en-us/documentation/articles/dns-overview/), if you want to learn more about Azure DNS.

## 2 Register Azure DNS

After you create Azure DNS service via ARM tempaltes or manually, you need to register it in your domain-name service provider.

### 2.1 Get your Name Server Domain Name

```
azure network dns record-set show --resource-group <resource-group> --dns-zone-name <dns-zone-name> --name "@" --type NS
```

Example:

```
azure network dns record-set show --resource-group cfc6f8ef9cabd8490687806b --dns-zone-name mslovelinux.com --name "@" --type NS
```

Sample Output:

```
info:    Executing command network dns record-set show
+ Looking up the DNS Record Set "@" of type "NS"
data:    Id                              : /subscriptions/########-####-####-####-############/resourceGroups/cfc6f8ef9cabd8490687806b/providers/Microsoft.Network/dnszones/mslovelinux.com/NS/@
data:    Name                            : @
data:    Type                            : Microsoft.Network/dnszones
data:    Location                        : global
data:    TTL                             : 3600
data:    NS records
data:        Name server domain name     : ns1-07.azure-dns.com.
data:        Name server domain name     : ns2-07.azure-dns.net.
data:        Name server domain name     : ns3-07.azure-dns.org.
data:        Name server domain name     : ns4-07.azure-dns.info.
data:
info:    network dns record-set show command OK
```

You can get four `Name server domain name` from the output.

### 2.2 Register your Azure DNS Name

It may differ from each provider, but the process is basically same. You can usually get the guidance in your domain-name service provider about how to register your name server domain name.
