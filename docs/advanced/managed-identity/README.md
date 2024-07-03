# Use Managed Identity

[Managed Identity](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview) (formerly known as Managed Service Identity (MSI)) provides Azure services with an automatically managed identity in Azure AD. You can use the identity to authenticate to any service that supports Azure AD authentication, including Key Vault, without any credentials in your code.

## Overview

Azure CPI `v35.5.0+` supports Azure Managed Identity. The supported features:

* Managed identity on VMs can be configured via `vm_extensions`, which means the VM will be managed identity enabled. Your codes on the VM can use a managed identity to request access tokens for services that support Azure AD authentication.

* Managed identity can be used as credential source. CPI will use the identity on BOSH director to manage Azure resources.

* Both system-assigned and user-assigned managed identity are supported.

Azure CPI `v35.5.0+` does **NOT** support the following features. You need to do them manually. Please see the [appendix](#appendix-azure-managed-identity).

* Create a managed identity.

* Assign a role to the managed identity.

## Configure Managed Identity on VMs

1. Create a `vm_extension` with the property `managed_identity`, if you want to configure managed identity on VMs in an instance group.

    ```
    vm_extensions:
    - name: enable-managed-identity
      cloud_properties:
        managed_identity:
          type: UserAssigned
          user_assigned_identity_name: <my-identiy-name>
    ```

1. Specify the above VM extension to the instance group.

1. (Optional) Configure `default_managed_identity` in CPI global configurations, if you want to configure the default managed identity to all VMs. If not, skip this step.

    ```
    azure:
      environment: AzureCloud
      subscription_id: 3c39a033-c306-4615-a4cb-260418d63879
      default_managed_identity:
        type: UserAssigned
        user_assigned_identity_name: <my-identiy-name>
      resource_group_name: bosh-res-group
      storage_account_name: boshstore
      ssh_user: vcap
      ssh_public_key: "ssh-rsa AAAAB3N...6HySEF6IkbJ"
      default_security_group: nsg-azure
    ```

1. Create a BOSH deployment with `bosh deploy`.

## Use Managed Identity as Credential Source

1. Configure CPI to create the BOSH director using managed identity.

    1. A jumpbox Linux VM on Azure is **required**, where you run `bosh create-env`. If your jumpbox is outside of Azure, you need to configure `credentials_source` to `static` and use Azure service principal (`tenant_id`, `client_id` and `client_secret`) to create your BOSH director. You can jump to next step `Configure managed identity in the resource pool of BOSH director VM`.

    1. Configure managed identity on your jumpbox VM. Please see the [appendix](#appendix-azure-managed-identity).

    1. Configure `credentials_source` to `managed_identity` in [Cloud Provider Block](https://bosh.io/docs/deployment-manifest/#cloud-provider). You don't need to specify service principal any longer.

      ```
      - type: replace
        path: /cloud_provider/properties/azure?
        value:
          environment: AzureCloud
          subscription_id: 3c39a033-c306-4615-a4cb-260418d63879
          credentials_source: managed_identity
          resource_group_name: bosh-res-group
          storage_account_name: boshstore
          ssh_user: vcap
          ssh_public_key: "ssh-rsa AAAAB3N...6HySEF6IkbJ"
          default_security_group: nsg-azure
      ```

    1. (Optional) Configure `managed_identity_resource_id` to the specific Azure resource ID of the managed identity you want to use for calls made from your jumpbox VM. This can be set to prevent issues when the jumpbox VM being used to create the BOSH director has more than one managed identity assigned to it.

      ```
      - type: replace
        path: /cloud_provider/properties/azure?/managed_identity_resource_id?
        value: /subscriptions/<my-subscription>/resourcegroups/<my-resource-group>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<my-identity-name>
      ```

1. Configure managed identity in the resource pool of BOSH director VM. Please make sure the managed identity has been assigned a `Contributor` role. Please see [Assign a role to a user-assigned managed identity](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/how-to-manage-ua-identity-portal#assign-a-role-to-a-user-assigned-managed-identity).

    ```
    - type: replace
      path: /resource_pools/name=vms/cloud_properties?/managed_identity?
      value:
        type: UserAssigned
        user_assigned_identity_name: <your-identity-name>
    ```

1. Configure BOSH director to use managed identity as [credential source](https://bosh.io/jobs/azure_cpi?source=github.com/cloudfoundry/bosh-azure-cpi-release&version=35.5.0#p%3dazure).

    ```
    - type: replace
      path: /instance_groups/name=bosh/properties/azure?
      value:
        environment: AzureCloud
        subscription_id: 3c39a033-c306-4615-a4cb-260418d63879
        credentials_source: managed_identity
        resource_group_name: bosh-res-group
        storage_account_name: boshstore
        ssh_user: vcap
        ssh_public_key: "ssh-rsa AAAAB3N...6HySEF6IkbJ"
        default_security_group: nsg-azure
    ```

1. Deploy your BOSH director with `bosh create-env`. Then CPI on the director VM can use the managed identity to request access tokens to create Azure resources.

## Appendix: Azure Managed Identity

### System-assigned managed identity

1. Create a system-assigned managed identity.

    * [Create a system-assigned managed identity using the Azure portal](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/qs-configure-portal-windows-vm#system-assigned-managed-identity)

    * [Create a system-assigned managed identity using the Azure CLI](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/qs-configure-cli-windows-vm#system-assigned-managed-identity)

1. [Assign a role to a system-assigned managed identity](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/tutorial-linux-vm-access-arm#grant-your-vm-access-to-a-resource-group-in-azure-resource-manager)

### User-assigned managed identity

1. Create a user-assigned managed identity.

    * [Create a user-assigned managed identity using the Azure portal](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/how-to-manage-ua-identity-portal#create-a-user-assigned-managed-identity)

    * [Create a user-assigned managed identity using the Azure CLI](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/how-to-manage-ua-identity-cli#create-a-user-assigned-managed-identity)

1. [Assign a role to a user-assigned managed identity](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/how-to-manage-ua-identity-portal#assign-a-role-to-a-user-assigned-managed-identity)
