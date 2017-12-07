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

For example: The deployment will create a DNS Record Set "*" of type "A" for the system domain `mslinux.love`, and map it to the public IP address of Cloud Foundry `123.123.123.123`. 

### 1.2 Manually

You can also use Azure CLI to manage DNS zones and records manually.

1. Create a DNS zone

    ```
    az network dns zone create --resource-group $resource-group-name --name $name
    ```

    Example:

    ```
    $ az network dns zone create --resource-group cfc6f8ef9cabd8490687806b --name mslinux.love
    {
      "etag": "00000002-0000-0000-1d04-e4253e67d301",
      "id": "/subscriptions/########-####-####-####-############/resourceGroups/cfc6f8ef9cabd8490687806b/providers/Microsoft.Network/dnszones/mslinux.love",
      "location": "global",
      "maxNumberOfRecordSets": 5000,
      "name": "mslinux.love",
      "nameServers": [
        "ns1-07.azure-dns.com.",
        "ns2-07.azure-dns.net.",
        "ns3-07.azure-dns.org.",
        "ns4-07.azure-dns.info."
      ],
      "numberOfRecordSets": 2,
      "resourceGroup": "cfc6f8ef9cabd8490687806b",
      "tags": {},
      "type": "Microsoft.Network/dnszones"
    }
    ```

1. Create DNS records

    1. Create a record set

        ```
        az network dns record-set a create --resource-group $resource_group_name --zone-name $zone_name --name $name --ttl $dns_ttl
        ```

        Example:

        ```
        $ az network dns record-set a create --resource-group cfc6f8ef9cabd8490687806b --zone-name mslinux.love --name "*" --ttl 3600
        {
          "etag": "325965ff-2b08-4ead-95f9-72dc2094976f",
          "fqdn": "*.mslinux.love.",
          "id": "/subscriptions/########-####-####-####-############/resourceGroups/cfc6f8ef9cabd8490687806b/providers/Microsoft.Network/dnszones/mslinux.love/A/*",
          "metadata": null,
          "name": "*",
          "resourceGroup": "cfc6f8ef9cabd8490687806b",
          "ttl": 3600,
          "type": "Microsoft.Network/dnszones/A"
        }
        ```

    1. Add a record into the resord set

        ```
        az network dns record-set a add-record --resource-group $resource_group_name --zone-name $zone_name --record-set-name $record_set_name --ipv4-address $ipv4_address
        ```

        Example:

        ```
        $ az network dns record-set a add-record --resource-group cfc6f8ef9cabd8490687806b --zone-name mslinux.love --record-set-name "*" --ipv4-address "123.123.123.123"                    {
          "arecords": [
            {
              "ipv4Address": "123.123.123.123"
            }
          ],
          "etag": "2357298b-7203-4d60-96be-2171be6c51ff",
          "fqdn": "*.mslinux.love.",
          "id": "/subscriptions/########-####-####-####-############/resourceGroups/cfc6f8ef9cabd8490687806b/providers/Microsoft.Network/dnszones/mslinux.love/A/*",
          "metadata": null,
          "name": "*",
          "resourceGroup": "cfc6f8ef9cabd8490687806b",
          "ttl": 3600,
          "type": "Microsoft.Network/dnszones/A"
        }
        ```

Please click [**HERE**](https://azure.microsoft.com/en-us/documentation/articles/dns-overview/), if you want to learn more about Azure DNS.

## 2 Register Azure DNS

After you create Azure DNS service via ARM tempaltes or manually, you need to register it in your domain-name service provider.

### 2.1 Get your Name Server Domain Name

```
az network dns record-set ns show --resource-group $resource_group_name --zone-name $zone_name --name "@"
```

Example:

```
$ az network dns record-set ns show --resource-group cfc6f8ef9cabd8490687806b --zone-name mslinux.love --name "@"
{
  "etag": "10bdcfe0-ec2b-4fd2-a934-e07483111aea",
  "fqdn": "mslinux.love.",
  "id": "/subscriptions/########-####-####-####-############/resourceGroups/cfc6f8ef9cabd8490687806b/providers/Microsoft.Network/dnszones/mslinux.love/NS/@",
  "metadata": null,
  "name": "@",
  "nsRecords": [
    {
      "nsdname": "ns1-07.azure-dns.com."
    },
    {
      "nsdname": "ns2-07.azure-dns.net."
    },
    {
      "nsdname": "ns3-07.azure-dns.org."
    },
    {
      "nsdname": "ns4-07.azure-dns.info."
    }
  ],
  "resourceGroup": "cfc6f8ef9cabd8490687806b",
  "ttl": 172800,
  "type": "Microsoft.Network/dnszones/NS"
}
```

You can get four `nsdname` from the output.

### 2.2 Register your Azure DNS Name

It may differ from each provider, but the process is basically same. You can usually get the guidance in your domain-name service provider about how to register your name server domain name.
