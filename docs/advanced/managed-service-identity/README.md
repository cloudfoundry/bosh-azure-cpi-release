# Use Managed Service Identity

[Managed Service Identity (MSI)](https://docs.microsoft.com/en-us/azure/active-directory/managed-service-identity/overview) provides Azure services with an automatically managed identity in Azure AD. You can use the identity to authenticate to any service that supports Azure AD authentication, including Key Vault, without any credentials in your code. This tutorial shows you how to enable [Managed Service Identity for a Linux Virtual Machine](https://docs.microsoft.com/en-us/azure/active-directory/managed-service-identity/tutorial-linux-vm-access-arm), and then use that identity to deploy BOSH director and Cloud Foundry.

## Requirements

* Azure CPI v35.5.0+ is required.

* You have a jumpbox Linux VM on Azure. All the bosh commands need to run in this VM.

## Deploy BOSH Director

### Enable Managed Service Identity on your jumpbox VM

A Virtual Machine Managed Service Identity enables you to get access tokens from Azure AD without you needing to put credentials into your code. Enabling Managed Service Identity on a VM, does two things: registers your VM with Azure Active Directory to create its managed identity, and it configures the identity on the VM.

1. Select the **Virtual Machine** that you want to enable Managed Service Identity on.

1. On the left navigation bar click **Configuration**.

1. You see **Managed Service Identity**. To register and enable the Managed Service Identity, select **Yes**, if you wish to disable it, choose **No**.

1. Ensure you click **Save** to save the configuration.

### Grant your VM access to a subscription

Using Managed Service Identity, your code can get access tokens to authenticate to resources that support Azure AD authentication. The Azure Resource Manager API supports Azure AD authentication. First, we need to grant this VM's identity access to a resource in Azure Resource Manager, in this case the **Subscription** in which the VM is contained.

1. Navigate to the tab for **Subscriptions**.

1. Select the specific **Subscription**.

1. Go to **Access control (IAM)** in the left panel.

1. Click to **Add** a new role assignment for your VM. Choose Role as *Contributor*.

1. In the next dropdown, **Assign access to** the resource **Virtual Machine**.

1. Next, ensure the proper subscription is listed in the **Subscription** dropdown. And for **Resource Group**, select **All resource groups**.

1. Finally, in **Select** choose your Linux Virtual Machine in the dropdown and click **Save**.

### Configure your CPI global configuration

1. Add `managed_service_identity.enabled`, and remove `client_id` and `client_secret`.

    ```diff
    properties:
      azure:
        environment: AzureCloud
        subscription_id: 3c39a033-c306-4615-a4cb-260418d63879
        tenant_id: 0412d4fa-43d2-414b-b392-25d5ca46561da
    -    client_id: 33e56099-0bde-8z93-a005-89c0f6df7465
    -    client_secret: client-secret
    +    managed_service_identity:
    +      enabled: true
        resource_group_name: bosh-res-group
        storage_account_name: boshstore
        ssh_user: vcap
        ssh_public_key: "ssh-rsa AAAAB3N...6HySEF6IkbJ"
        default_security_group: nsg-azure
    ```

1. Deploy your BOSH director using `bosh creat-env`.

## Deploy Cloud Foundry

1. Do the same thing to enable MSI on your **director VM** and grant your VM access to a subscription.

1. Deploy your Cloud Foundry.
