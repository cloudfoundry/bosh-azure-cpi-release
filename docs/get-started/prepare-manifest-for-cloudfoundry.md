# Prepare the manifest for Cloud Foundry

>**NOTE:**
  * The section shows how to configure a get-started manifest to deploy Cloud Foundry. For a more robust deployment, please refer to [**deploy-cloudfoundry-for-enterprise**](./deploy-cloudfoundry-for-enterprise.md)
  * All the following commands must be run in your dev-box.

A manifest is needed to deploy Cloud Foundry. In this section, we will show how to configure the manifest.

We provide two sample configurations:

* [**single-vm-cf-224.yml**](../example_manifests/single-vm-cf-224.yml): Configuration to deploy Single-VM Cloud Foundry.
* [**multiple-vm-cf-224.yml**](../example_manifests/multiple-vm-cf-224.yml): Configuration to deploy Multi-VM Cloud Foundry.

You can choose one of them based on your needs.

You should replace the **BOSH-DIRECTOR-UUID**, **VNET-NAME**, **SUBNET-NAME**, **RESERVED-IP** and **SSL-CERT-AND-KEY** properties.

1. Configure **BOSH-DIRECTOR-UUID**

  Logon your BOSH director with below command.
  
  ```
  bosh target 10.0.0.4 # Username: admin, Password: admin
  ```
  
  Get the UUID of your BOSH director with below command.
  
  ```
  bosh status
  ```
  
  Copy **Director.UUID** to replace **BOSH-DIRECTOR-UUID** in the YAML file for Cloud Foundry.
  
  Sample output:
  
  ```
  Config
       /home/vcap/.bosh_config
  
  Director
  Name       bosh
  URL        https://10.0.0.4:25555
  Version    1.0000.0 (00000000)
  User       admin
  UUID       640a7bf6-a39c-414e-83b9-d1bef9d6f701
  CPI        cpi
  dns        disabled
  compiled_package_cache disabled
  snapshots  enabled
  
  Deployment
  not set
  ```

2. Configure **VNET-NAME**, **SUBNET-NAME** and **RESERVED-IP**

  * **VNET-NAME** - the virtual network name
  * **SUBNET-NAME** - the subnet name for Cloud Foundry
  * **RESERVED-IP**
    * If your BOSH is deployed using ARM templates, you can find `cf-ip` in `~/settings`.
    * If your BOSH is deployed manually, you can get the public IP for Cloud Foundry [**HERE**](./deploy-bosh-manually.md#get_public_ip). Another way is to find the IP from your resource group on Azure Portal.

3. Configure **SSL-CERT-AND-KEY**

  You should use your certificate and key. And this is an example to show how to generate them.
  
  ```
  openssl genrsa -out bosh.key 2048
  openssl req -new -x509 -days 365 -key bosh.key -out bosh_cert.pem
  ```
  
  You need to concatenate the contents of `bosh_cert.pem` and `bosh.key` to replace **SSL-CERT-AND-KEY**.

  Example:

  ```
  ha_proxy:
    ssl_pem: |
      -----BEGIN CERTIFICATE-----
      MIIDXTCCAkWgAwIBAgIJAJWo1rwt2B2IMA0GCSqGSIb3DQEBCwUAMEUxCzAJBgNV
      BAYTAkFVMRMwEQYDVQQIDApTb21lLVN0YXRlMSEwHwYDVQQKDBhJbnRlcm5ldCBX
      aWRnaXRzIFB0eSBMdGQwHhcNMTUxMTAxMTAyODA5WhcNMTYxMDMxMTAyODA5WjBF
      MQswCQYDVQQGEwJBVTETMBEGA1UECAwKU29tZS1TdGF0ZTEhMB8GA1UECgwYSW50
      ZXJuZXQgV2lkZ2l0cyBQdHkgTHRkMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIB
      CgKCAQEAzmgXmtJRjOP3Rj1Btu0TKdez/nymTVb4ecsXV/jlCZLcOQgm/rPtTShM
      Ai0tmRbjRCNxdYteOJIB6RiUe8dhv8r4LQ/GrFQboykeFnh0KNoNwb3FolKqEbvQ
      B+nbgFo7AEnK7yR/+Cu7rjl4lIHwp34/tFoT5ox5f3MYX259Zjxn2Rke2QG480G1
      wfRVg1RxcbQAglsWMQKhmia4Lzo3aA6rI1Y+/dcsej/0WG3KGRz3QP03D6Efyq1L
      LcDrE5+uMxPqTeTIgVuzRedyUWPM/PNnIxQwYyk4ETX+OKJcEjQZbYzJ9cxm/r+b
      acIgV8QAv5bUY2CGC6KMsOsjLMR6/wIDAQABo1AwTjAdBgNVHQ4EFgQUuPydhm2c
      GDtbsQ+i4JBkLSrVcmgwHwYDVR0jBBgwFoAUuPydhm2cGDtbsQ+i4JBkLSrVcmgw
      DAYDVR0TBAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAL3gMHbLJI+znjAUZswR0
      u/+YohEjujYa5Y69Z+xuv3N+CJgYBM38j7yJsica3SzAgRYwl6+04Xox++V82CB/
      yYM7xJsxu5q3fYfnQQB8XY0TNWG7QZdvhOIG1mTjCe04x80XjHDgKsCAdyvvTiTc
      YFyy4VS1MlhPe2e6i/+wXdKj5Qn0COu6Ih536uTyo0TTljMZGuYPw21QE0Qo2y+3
      EJvv+bN+XPrZzELl6p0FymgJV8mFkYOqXD5C5d1vYzmjBSwdjNNXBXRovoEjoJ9R
      LDYGT94+X4UkI3asd6fn4eg9iuaUNC+WxsSnKa9z5qLgyMSF7GsZqKjGcoQjuiDj
      AQ==
      -----END CERTIFICATE-----
      -----BEGIN RSA PRIVATE KEY-----
      MIIEogIBAAKCAQEAzmgXmtJRjOP3Rj1Btu0TKdez/nymTVb4ecsXV/jlCZLcOQgm
      /rPtTShMAi0tmRbjRCNxdYteOJIB6RiUe8dhv8r4LQ/GrFQboykeFnh0KNoNwb3F
      olKqEbvQB+nbgFo7AEnK7yR/+Cu7rjl4lIHwp34/tFoT5ox5f3MYX259Zjxn2Rke
      2QG480G1wfRVg1RxcbQAglsWMQKhmia4Lzo3aA6rI1Y+/dcsej/0WG3KGRz3QP03
      D6Efyq1LLcDrE5+uMxPqTeTIgVuzRedyUWPM/PNnIxQwYyk4ETX+OKJcEjQZbYzJ
      9cxm/r+bacIgV8QAv5bUY2CGC6KMsOsjLMR6/wIDAQABAoIBAGAXGZYb/5clscJj
      ViqA6AD8yHDbOtiaeobIw49S8d2pHxj18KF2xiy7a9c/jRDOFPNtxK5COZUAdB8+
      MDIHujv9k9f2ljk31r34sGcpoHo8OVdOr6lH7qDe3JQyjNuOJhWWRQFb7q9sPK15
      V+dbLtvq7GFb5hPYpd9th5U17O8grWR6yOwhfEIJNSq/bbAhKc4cMRFGCeV+DRAR
      LMzdjRsfYWfMoHeOFeuBcSgV21wfjg0sCViQ2TN/tVp9bcr/bmzbje60jgnNdnzT
      VD7e/m0xNisZ0VMzBGPiKueyM1f0jOCNAu27KxeeSwsQNq5C07sxopp1iwWbmJlP
      Mk8ymCECgYEA92LcQNDcRYtGVd3xbGs3AKmcLgEeXrreVticqsnLJ0zmj7DBVTXw
      rI8MNGI2nnme+dhnr6sozAoKukE3jJaRvl94AwzeLNDHojZh6mhREXDPCSs2Gd3U
      iLeOJmmySW3p8woeyJXbBGOT29II9jSOYQTWxiM2+MCx1AOYHjoX/OkCgYEA1Zfz
      OAXPbRmzhfwavIbMQLWEHpRO7nD07ifE+zRyLzraRU6nCOzy9LQubLJPPVPZzKK/
      ZOKHt7ddM5WRo9NZz2+keNSQSw1d6SKjG4SPH0LG4iLCx/VpKWTG6l6k7xBc1mHe
      tqhnc7u7X+1qT5+Hs6YY/6q0wgKbfK0OuOh/J6cCfy1q+QTtU4NxDni1Rp2hEXgN
      q57GlczOggNvwVOZuLJ+a9X1nYkHXihQGu2DGoP90DIOiPq3ccYEEfQgBRLKkfdh
      j6b/tcqEiiI92bwvarLJAzmrtUMKdvqiuHZU8WaJx2nXcc9hs9QadArnhL2u6HTn
      bobx8CW7OuqxvjvObpkCgYEAnPGAskp6poS7B5k9oAdAL8/wW3PIJ6XyIsgwEhDw
      Ucnhtglb7NAGmU2HyzCdzsc9AwMWtS9KX/Co2A1vrTvQAv7akDpIKA2TUomz5bVa
      YLL1ZhX6n2iws8yr6GxQrqSMQq45Mme9VCm+PXc6pXToBlXmin3JQcEetNaIOdAE
      FoMCgYEAgB+qAAfoX1e7DOkqHHr4SJERzN3MQ7NlnaNf5K7FNzFBdNSrKbe20YQR
      MzSpkc9piBnf9REsmfwh/8GlDoJhZtwETEf2EtUeLPuywnyy2rFRB9yMNo9RdBYa
      EJz7EDFRyM34vKPVktA73suJQ1kzYX1ITUICPbuYObSF8vw5BTk=
      -----END RSA PRIVATE KEY-----
  ```

>**NOTE:**
  * **Never use the certificate and key in the example.**
  * If you set `enableDNSOnDevbox` true, the dev box can serve as a DNS and it has been pre-configured in example YAML file.
  * If you want to use your own domain name, you can replace all **cf.azurelovecf.com** in the example YAML file. And please replace **10.0.0.100** with the IP address of your DNS server.
