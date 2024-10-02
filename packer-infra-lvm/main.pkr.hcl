packer {
    required_version = "1.11.2"
    required_plugins {
        amazon = {
            source = "github.com/hashicorp/amazon"
            version = "1.3.2"
        }
        ansible = {
            version = "~> 1"
            source = "github.com/hashicorp/ansible"
            }
  
    }
}