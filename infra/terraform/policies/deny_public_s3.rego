# Policy: Public S3 Bucketを禁止
# Terraformのplan JSON出力に対してチェック

package terraform

import rego.v1

# S3 Bucket ACLがpublic-readの場合は禁止
deny contains msg if {
    resource := input.resource_changes[_]
    resource.type == "aws_s3_bucket_acl"
    acl := resource.change.after.acl
    acl in ["public-read", "public-read-write", "authenticated-read"]
    
    msg := sprintf("S3 Bucket ACL '%s' uses public ACL '%s'. This is not allowed.", [resource.address, acl])
}

# S3 Bucket Public Access Blockが無効の場合は警告
warn contains msg if {
    resource := input.resource_changes[_]
    resource.type == "aws_s3_bucket_public_access_block"
    resource.change.after.block_public_acls == false
    
    msg := sprintf("S3 Bucket '%s' has block_public_acls disabled. Consider enabling it.", [resource.address])
}

warn contains msg if {
    resource := input.resource_changes[_]
    resource.type == "aws_s3_bucket_public_access_block"
    resource.change.after.block_public_policy == false
    
    msg := sprintf("S3 Bucket '%s' has block_public_policy disabled. Consider enabling it.", [resource.address])
}
