provider "helm" {
  kubernetes {
    config_path = var.kube_config
  }
  #enable_tls         = true
}

provider "kubernetes" {
  config_path = var.kube_config
}

resource "kubernetes_namespace" "nginxIngress" {
  metadata {
    labels = {
      "certmanager.k8s.io/disable-validation" = "false"
    }

    name = var.ingressNamespace
  }
}

data "hcloud_floating_ip" "kubernetes" {
  with_selector = "ingressip=true"
}

resource "helm_release" "nginxIngress" {
  name  = "nginx-ingress"
  chart = "stable/nginx-ingress"

  namespace = var.ingressNamespace

  force_update  = true
  recreate_pods = true
  timeout       = 3600

  set {
    name  = "controller.replicaCount"
    value = var.ingressReplicas
  }
  set {
    name  = "controller.service.loadBalancerIP"
    value = data.hcloud_floating_ip.kubernetes.ip_address
  }
  //set {
  //  name = "controller.service.externalTrafficPolicy"
  //  value = "Local"
  //}

  depends_on = [kubernetes_namespace.nginxIngress]
}

resource "kubernetes_ingress" "ingress" {
  metadata {
    name      = "${var.kubernetes_prefix}-ingress"
    namespace = "default"
    annotations = {
      "cert-manager.io/cluster-issuer"             = "letsencrypt"
      "kubernetes.io/ingress.class"                = "nginx"
      "nginx.ingress.kubernetes.io/ssl-redirect"   = "true"
      "nginx.ingress.kubernetes.io/rewrite-target" = "/$1"

    }
  }
  spec {
    rule {
      host = "${var.kubernetes_prefix}.azure.dabetz.de"
      http {
        path {
          backend {
            service_name = "${var.kubernetes_prefix}-httpd"
            service_port = 80
          }
          path = "/(.*)"
        }
      }

    }
    tls {
      secret_name = "tls-secret"
      hosts       = ["${var.kubernetes_prefix}.azure.dabetz.de"]
    }
  }
}

