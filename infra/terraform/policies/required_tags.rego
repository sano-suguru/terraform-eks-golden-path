# Policy: 必須タグの確認
# Terraformのplan JSON出力に対してチェック

package terraform

import rego.v1

# 必須タグのリスト
required_tags := ["Environment", "Project", "ManagedBy"]

# タグをサポートするリソースタイプ
taggable_resources := [
    "aws_vpc",
    "aws_subnet",
    "aws_security_group",
    "aws_eks_cluster",
    "aws_eks_node_group",
    "aws_iam_role",
    "aws_internet_gateway"
]

# 必須タグが欠けている場合は警告
warn contains msg if {
    resource := input.resource_changes[_]
    is_taggable(resource.type)
    is_create_or_update(resource.change.actions)
    
    # tagsをチェック
    tags := get_tags(resource)
    
    # 必須タグが存在するか確認
    missing := missing_tags(tags)
    count(missing) > 0
    
    msg := sprintf("Resource '%s' is missing required tags: %v", [resource.address, missing])
}

# ヘルパー関数
is_taggable(resource_type) if {
    taggable_resources[_] == resource_type
}

is_create_or_update(actions) if {
    actions[_] == "create"
}

is_create_or_update(actions) if {
    actions[_] == "update"
}

get_tags(resource) := tags if {
    tags := resource.change.after.tags_all
} else := tags if {
    tags := resource.change.after.tags
} else := tags if {
    tags := {}
}

missing_tags(tags) := missing if {
    present := {key | tags[key]}
    required := {tag | tag := required_tags[_]}
    missing := required - present
}
}
