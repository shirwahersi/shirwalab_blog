+++
title = 'Deploying Argo CD with SSO using Microsoft Entra ID OIDC'
date = 2025-05-05T13:28:39+01:00
draft = false
+++




## Step 1: Entra ID App Registration Auth using OIDC

1.1 From the Microsoft Entra ID > App registrations menu, choose + New registration

1.2 Enter a Name for the application (e.g. Argo CD).

![argo sso ](/static/images/argocd/argo-sso1.png)

1.3 Specify who can use the application (e.g. Accounts in this organizational directory only).

1.3 Go to Branding & properties and add logo

![argo sso ](/static/images/argocd/argo-sso2.png)

**Configure platform web settings**

1.4 Go to Authentication -> Add a platform -> Web

![argo sso ](/static/images/argocd/argo-sso3.png)

* Platform: Web
* Redirect URI: https://argocd.int.shirwalab.net/auth/callback

![argo sso ](/static/images/argocd/argo-sso4.png)

**Configure additional platform settings for ArgoCD CLI**

1.5 Go to Authentication -> Add a platform -> Mobile and desktop application

* Platform: Mobile and desktop application
* Redirect URI: https://argocd.int.shirwalab.net:8085/auth/callback

![argo sso ](/static/images/argocd/argo-sso5.png)

1.6 Add credentials a new Entra ID App registration

1.7 From the Certificates & secrets menu, choose + New client secret
1.8 Enter a Name for the secret (e.g. ArgoCD-SSO).

![argo sso ](/static/images/argocd/argo-sso6.png)

> Make sure to copy and save generated value. This is a value for the `client_secret`.

![argo sso ](/static/images/argocd/argo-sso7.png)

**Setup permissions for Entra ID Application**

1.9 From the API permissions menu, choose + Add a permission

1.10 Find User.Read permission (under Microsoft Graph) and grant it to the created application:

![argo sso ](/static/images/argocd/argo-sso9.png)


**Associate an Entra ID group to your Entra ID App registration**

1.11 From the Microsoft Entra ID > Enterprise applications menu, search the App that you created (e.g. Argo CD).
* An Enterprise application with the same name of the Entra ID App registration is created when you add a new Entra ID App registration.

![argo sso ](/static/images/argocd/argo-sso8.png)

1.12 From the Users and groups menu of the app, add any users or groups requiring access to the service.

![argo sso ](/static/images/argocd/argo-sso10.png)

![argo sso ](/static/images/argocd/argo-sso11.png)


## Step 2 : Deploy Argo CD with Microsoft Entra ID OIDC Auth 

2.1 Create ArgoCD namespace and a secret containing the `client_secret` created in step 1.8.

```
data "aws_secretsmanager_secret" "entra-id" {
  name = "/homelab/entra-id/secrets"
}

data "aws_secretsmanager_secret_version" "entra-id" {
  secret_id = data.aws_secretsmanager_secret.entra-id.id
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "kubernetes_secret_v1" "argocd_app_secret" {
  metadata {
    name      = "argocd-oidc-secret"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "app.kubernetes.io/name"    = "argocd-oidc-secret"
      "app.kubernetes.io/part-of" = "argocd"
    }
  }

  data = {
    "oidc.azure.clientSecret" = jsondecode(data.aws_secretsmanager_secret_version.entra-id.secret_string)["argocd_client_secret"]
  }
}
```

2.2 Create Helm values files containing ArgoCD ingress and OIDC configuration.

```
# file: terraform/infra-kube-addons/files/helm/argocd/argocd-values.yaml
global:
  domain: argocd.int.shirwalab.net

server:
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: "ipa"
      nginx.ingress.kubernetes.io/ssl-passthrough: 'true'
      nginx.ingress.kubernetes.io/backend-protocol: 'HTTPS'
    tls: true

configs:
  rbac:
    policy.default: role:readonly
    policy.csv: |
       p, role:org-admin, applications, *, */*, allow
       p, role:org-admin, clusters, get, *, allow
       p, role:org-admin, repositories, get, *, allow
       p, role:org-admin, repositories, create, *, allow
       p, role:org-admin, repositories, update, *, allow
       p, role:org-admin, repositories, delete, *, allow
       g, "5e1e9f90-50fa-4e3a-9c64-e176020417b2", role:org-admin
    scopes: '[groups, email]'
  cm:
    admin.enabled: false
    oidc.config: |
      name: Azure
      issuer: https://login.microsoftonline.com/cacde176-a85a-48d6-b35f-33f36d79fe9f/v2.0
      clientID: c4ee1b01-010a-4657-a8f8-848a29bd81ed
      clientSecret: $argocd-oidc-secret:oidc.azure.clientSecret
      requestedIDTokenClaims:
        groups:
            essential: true
            value: "SecurityGroup"
      requestedScopes:
        - openid
        - profile
        - email
dex:
  enabled: false
```

2.3 Deploy Argo CD helm chart

```
resource "helm_release" "argocd" {
  name = "argocd"

  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = kubernetes_namespace.argocd.metadata[0].name
  create_namespace = false
  version          = "7.9.0"
  values           = ["${file("${path.module}/files/helm/argocd/argocd-values.yaml")}"]
}
```

## Step 3: Validation

<video src="/static/images/argocd/argocd-oidc-demo.mp4" width="1280" height="908" controls></video>

## Resources

* https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/microsoft/#entra-id-app-registration-auth-using-oidc
