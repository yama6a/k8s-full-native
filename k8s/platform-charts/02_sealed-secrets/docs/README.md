# Sealed Secrets

Sealed Secrets is a Kubernetes Custom Resource Definition Controller which allows you to store sensitive information in
Git repositories without compromising security.
It works by encrypting the secret data with a public key and then storing the encrypted data in a Kubernetes Custom
Resource Definition.

## Basic Usage (For Developers)

1. Create a SealedSecret manifest (see [example](example_sealedsecret_manifest.yaml))
2. Create a key under `spec.encryptedData.<your-key>` in the manifest
3. Encrypt a raw value using the [kubeseal](https://github.com/bitnami-labs/sealed-secrets#kubeseal) CLI tool. This
   sends the raw string to the cluster, which encrypts it using the private key and returns the encrypted value.:

    ```bash
     echo "some-password" | kubeseal --controller-namespace=sys-sealed-secrets --scope=namespace-wide -n my-app-namespace --raw
    ```
4. Copy the output and paste it into the value, e.g.:

    ```yaml
    apiVersion: bitnami.com/v1alpha1
    kind: SealedSecret
    metadata:
      name: my-secret
      namespace: my-app-namespace
      annotations:
        sealedsecrets.bitnami.com/namespace-wide: "true"
    spec:
      encryptedData:
        mykey: VGhpcyBpcyBub3QgcmVhbCB5b3UgZm9vbCEK # encrypted value goes here
      template:
        metadata:
          name: my-secret
          namespace: my-app-namespace
    ```
5. Apply the manifest:

    ```bash
    kubectl apply -f my-sealedsecret.yaml
    ```
