# Policy: Security Groupで0.0.0.0/0からのSSH(22)を禁止
# Terraformのplan JSON出力に対してチェック

package terraform

# 違反を検出するルール
deny[msg] {
    # Security Groupのingress ruleをチェック
    resource := input.resource_changes[_]
    resource.type == "aws_security_group"
    ingress := resource.change.after.ingress[_]
    ingress.cidr_blocks[_] == "0.0.0.0/0"
    ingress.from_port <= 22
    ingress.to_port >= 22
    
    msg := sprintf("Security Group '%s' allows SSH (port 22) from 0.0.0.0/0. This is not allowed.", [resource.address])
}

# Security Groupで0.0.0.0/0からの全ポートを禁止
deny[msg] {
    resource := input.resource_changes[_]
    resource.type == "aws_security_group"
    ingress := resource.change.after.ingress[_]
    ingress.cidr_blocks[_] == "0.0.0.0/0"
    ingress.from_port == 0
    ingress.to_port == 0
    ingress.protocol == "-1"
    
    msg := sprintf("Security Group '%s' allows all traffic from 0.0.0.0/0. This is not allowed.", [resource.address])
}
