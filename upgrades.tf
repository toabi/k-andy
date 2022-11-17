data "kubectl_file_documents" "upgrade_controller" {
  content = var.enable_upgrade_controller ? templatefile("${path.module}/manifests/upgrade-controller.yaml", {
    kubectl_image_tag            = var.upgrade_controller_kubectl_image_tag
    upgrade_controller_image_tag = var.upgrade_controller_image_tag
  }) : ""
}

resource "kubectl_manifest" "upgrade_controller" {
  for_each  = data.kubectl_file_documents.upgrade_controller.manifests
  yaml_body = each.value
}

resource "kubectl_manifest" "upgrade_plan_control_plane" {
  count = var.upgrade_k3s_target_version != null && var.enable_upgrade_controller ? 1 : 0
  yaml_body = yamlencode({
    apiVersion = "upgrade.cattle.io/v1"
    kind       = "Plan"
    metadata = {
      labels = {
        "k3s-upgrade" = "server"
      }
      name      = "k3s-server"
      namespace = "system-upgrade"
    }
    spec = {
      version            = var.upgrade_k3s_target_version
      concurrency        = 1
      cordon             = true
      serviceAccountName = "system-upgrade"
      upgrade = {
        image = "rancher/k3s-upgrade"
      }
      nodeSelector = {
        matchExpressions = [
          {
            "key"      = "k3s-upgrade"
            "operator" = "Exists"
          },
          {
            "key"      = "k3s-upgrade"
            "operator" = "NotIn"
            "values" = [
              "disabled",
              "false",
            ]
          },
          {
            "key"      = "node-role.kubernetes.io/master"
            "operator" = "In"
            "values" = [
              "true",
            ]
          },
        ]
      }
      tolerations = concat([
        {
          "key"      = "node-role.kubernetes.io/master"
          "operator" = "Exists"
          "effect"   = "NoSchedule"
        },
        {
          "key"      = "CriticalAddonsOnly"
          "operator" = "Exists"
          "effect"   = "NoExecute"
        },
      ], var.upgrade_node_additional_tolerations)
    }
  })
}

resource "kubectl_manifest" "upgrade_plan_agents" {
  count = var.upgrade_k3s_target_version != null && var.enable_upgrade_controller ? 1 : 0
  yaml_body = yamlencode({
    apiVersion = "upgrade.cattle.io/v1"
    kind       = "Plan"
    metadata = {
      labels = {
        "k3s-upgrade" = "agent"
      }
      name      = "k3s-agent"
      namespace = "system-upgrade"
    }
    spec = {
      version     = var.upgrade_k3s_target_version
      concurrency = 1
      drain = {
        force                    = true
        skipWaitForDeleteTimeout = 60
      }
      serviceAccountName = "system-upgrade"
      prepare = {
        args = [
          "prepare",
          "k3s-server",
        ]
        image = "rancher/k3s-upgrade"
      }
      upgrade = {
        image = "rancher/k3s-upgrade"
      }
      nodeSelector = {
        matchExpressions = [
          {
            "key"      = "k3s-upgrade"
            "operator" = "Exists"
          },
          {
            "key"      = "k3s-upgrade"
            "operator" = "NotIn"
            "values" = [
              "disabled",
              "false",
            ]
          },
          {
            "key"      = "node-role.kubernetes.io/master"
            "operator" = "NotIn"
            "values" = [
              "true",
            ]
          },
        ]
      }
      tolerations = var.upgrade_node_additional_tolerations
    }
  })
}

resource "kubectl_manifest" "ubuntu_upgrade_config" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind = "Secret"
    metadata = {
      name = "ubuntu-upgrade"
      namespace = "system-upgrade"
    }
    stringData = {
      "upgrade.sh" = <<EOF
#!/bin/sh
apt-get update -y
apt-get upgrade -y
EOF
    }
  })
}


resource "kubectl_manifest" "upgrade_plan_ubuntu" {
  count = var.upgrade_k3s_target_version != null && var.enable_upgrade_controller ? 1 : 0
  yaml_body = yamlencode({
    apiVersion = "upgrade.cattle.io/v1"
    kind       = "Plan"
    metadata = {
      labels = {
        "k3s-upgrade" = "ubuntu"
      }
      name      = "ubuntu-upgrade"
      namespace = "system-upgrade"
    }
    spec = {
      version     = data.hcloud_image.ubuntu.os_version
      concurrency = 1
      nodeSelector = {
        matchExpressions = [
          {
            "key"      = "ubuntu-upgrade"
            "operator" = "Exists"
          },
          {
            "key"      = "ubuntu-upgrade"
            "operator" = "NotIn"
            "values" = [
              "disabled",
              "false",
            ]
          }
        ]
      }
      drain = {
        force                    = true
        skipWaitForDeleteTimeout = 60
      }
      serviceAccountName = "system-upgrade"
      secrets = [
        {
          name = "ubuntu-upgrade"
          path = "/host/run/system-upgrade/secrets/ubuntu-upgrade"
        }
      ]
      upgrade = {
        image = "ubuntu"
        command = ["chroot", "/host"]
        args = ["sh", "/run/system-upgrade/secrets/ubuntu-upgrade/upgrade.sh"]
      }
      tolerations = var.upgrade_node_additional_tolerations
    }
  })
}
