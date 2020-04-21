locals {
  random_kubeconfig_path = "${path.module}/${uuid()}.conf"
  clusterIssuer_file     = "${path.module}/clusterIssuer.yaml"
}

provider "hcloud" {
  token = var.HCLOUD_TOKEN
}

data "helm_repository" "jetstack" {
  name = "jetstack"
  url  = "https://charts.jetstack.io"
}

resource "kubernetes_namespace" "certmanager" {
  metadata {
    name = var.certmanagerNamespace
  }
}

resource "null_resource" "certManagerCRD" {

  provisioner "local-exec" {
    command = "cat ${var.kube_config} > $KUBECONFIG; kubectl apply --validate=false -f ${var.cert-manager-crd}; EXITCODE=$?;rm ${local.random_kubeconfig_path}; exit $EXITCODE"

    environment = {
      KUBECONFIG = local.random_kubeconfig_path
    }
  }
}

data "template_file" "clusterIssuer" {
  template = <<EOT
apiVersion: cert-manager.io/v1alpha2
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $${email_address}
    privateKeySecretRef:
      name: letsencrypt
    solvers:
    - http01:
        ingress:
          class: nginx
EOT

  vars = {
    email_address = var.email_address
  }
}

resource "local_file" "clusterIssuer" {
  filename = local.clusterIssuer_file
  content  = data.template_file.clusterIssuer.rendered
}

resource "null_resource" "clusterIssuer" {


  triggers = {
    trigger = data.template_file.clusterIssuer.rendered
  }

  provisioner "local-exec" {
    command = "cat ${var.kube_config} > $KUBECONFIG; kubectl apply -f ${local.clusterIssuer_file}; EXITCODE=$?;rm $KUBECONFIG; exit $EXITCODE"

    environment = {
      KUBECONFIG = local.random_kubeconfig_path
    }
  }

  depends_on = [helm_release.certManager]

}

resource "helm_release" "certManager" {
  name       = "cert-manager"
  chart      = "jetstack/cert-manager"
  repository = data.helm_repository.jetstack.metadata[0].name

  namespace = var.certmanagerNamespace
  #version = "v0.12.0"

  set {
    name  = "ingressShim.defaultIssuerName"
    value = "letsencrypt"
  }

  set {
    name  = "ingressShim.defaultIssuerKind"
    value = "ClusterIssuer"
  }

  timeout = 3600

  depends_on = [null_resource.certManagerCRD]
}
