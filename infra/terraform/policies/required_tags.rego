# Policy: 必須タグの確認
# Terraformのplan JSON出力に対してチェック

package terraform

import rego.v1

# 必須タグのリスト
required_tags := {"Environment", "Project", "ManagedBy"}

# タグをサポートするリソースタイプ
taggable_resources := {
    "aws_vpc",
    "aws_subnet",
    "aws_security_group",
    "aws_eks_cluster",
    "aws_eks_node_group",
    "aws_iam_role",
    "aws_internet_gateway",
}

# 必須タグが欠けている場合は警告
warn contains msg if {
    resource := input.resource_changes[_]
    resource.type in taggable_resources
    resource.change.actions[_] in ["create", "update"]
    
    # tags_allまたはtagsをチェック
    tags := object.get(resource.change.after, "tags_all", object.get(resource.change.after, "tags", {}))
    
    # 必須タグが存在するか確認
    missing := required_tags - {key | tags[key]}
    count(missing) > 0
    
    msg := sprintf("Resource '%s' is missing required tags: %v", [resource.address, missing])
}
