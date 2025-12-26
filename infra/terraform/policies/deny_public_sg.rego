# Policy: Security Groupで0.0.0.0/0からのSSH(22)を禁止
# Terraformのplan JSON出力に対してチェック

package terraform

import rego.v1

# 違反を検出するルール
deny contains msg if {
    # Security Groupのingress ruleをチェック
    resource := input.resource_changes[_]
    resource.type == "aws_security_group"
    resource.change.after.ingress[_].cidr_blocks[_] == "0.0.0.0/0"
    resource.change.after.ingress[_].from_port <= 22
    resource.change.after.ingress[_].to_port >= 22
    
    msg := sprintf("Security Group '%s' allows SSH (port 22) from 0.0.0.0/0. This is not allowed.", [resource.address])
}

# Security Groupで0.0.0.0/0からの全ポートを禁止
deny contains msg if {
    resource := input.resource_changes[_]
    resource.type == "aws_security_group"
    resource.change.after.ingress[_].cidr_blocks[_] == "0.0.0.0/0"
    resource.change.after.ingress[_].from_port == 0
    resource.change.after.ingress[_].to_port == 0
    resource.change.after.ingress[_].protocol == "-1"
    
    msg := sprintf("Security Group '%s' allows all traffic from 0.0.0.0/0. This is not allowed.", [resource.address])
}
