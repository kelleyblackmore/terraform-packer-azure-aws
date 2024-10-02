locals{
    timestamp = regex("[^:]+", timestamp())
    formatted_project_name = format("%s-%s", var.project_name, local.timestamp)
    formatted_vpc_name = format("%s-vpc", local.formatted_project_name)
    formatted_subnet_name = format("%s-subnet", local.formatted_project_name)

}