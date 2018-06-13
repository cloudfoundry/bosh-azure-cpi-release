#!/usr/bin/env ruby
# frozen_string_literal: true

load 'helpers.rb'

# --------------------------------- test ------------------------------------#
# 1. migrate: unmanaged v24 -> unmanaged vNext

# 1.1 create resources using cpi v24
cpi = get_cpi(@upstream_repo, 'v24', false)

resource_pool = {
  'instance_type' => 'Standard_F2',
  'assign_dynamic_public_ip' => true,
  'availability_set' => 'unmanaged-avset',
  'storage_account_name' => @vm_storage_account_name,
  'storage_account_type' => 'Standard_LRS'
}

instance_id = create_vm(cpi, resource_pool)
disk_id_1 = create_disk(cpi, instance_id: instance_id)
disk_id_2 = create_disk(cpi, instance_id: nil)
attach_disk(cpi, instance_id, disk_id_1)
attach_disk(cpi, instance_id, disk_id_2)

# 1.2 check and delete resources using new cpi
cpi = get_cpi(@test_repo, @test_branch, false)

check_vm(cpi, instance_id)
check_disk(cpi, disk_id_1, instance_id: instance_id)
check_disk(cpi, disk_id_2, instance_id: instance_id)

detach_disk(cpi, instance_id, disk_id_1)
detach_disk(cpi, instance_id, disk_id_2)

attach_disk(cpi, instance_id, disk_id_1)
attach_disk(cpi, instance_id, disk_id_2)

detach_disk(cpi, instance_id, disk_id_1)
detach_disk(cpi, instance_id, disk_id_2)

delete_disk(cpi, disk_id_1)
delete_disk(cpi, disk_id_2)

delete_vm(cpi, instance_id)

# 2. migrate: managed v24 -> managed vNext

# 2.1 create resources using cpi v24
cpi = get_cpi(@upstream_repo, 'v24', true)

resource_pool = {
  'instance_type' => 'Standard_F2',
  'assign_dynamic_public_ip' => true,
  'availability_set' => 'managed-avset'
}

instance_id = create_vm(cpi, resource_pool)
disk_id_1 = create_disk(cpi, instance_id: instance_id)
disk_id_2 = create_disk(cpi, instance_id: nil)
attach_disk(cpi, instance_id, disk_id_1)
attach_disk(cpi, instance_id, disk_id_2)

# 2.2 check and delete resources using new cpi
cpi = get_cpi(@test_repo, @test_branch, true)

check_vm(cpi, instance_id)
check_disk(cpi, disk_id_1, instance_id: instance_id)
check_disk(cpi, disk_id_2, instance_id: instance_id)

detach_disk(cpi, instance_id, disk_id_1)
detach_disk(cpi, instance_id, disk_id_2)

attach_disk(cpi, instance_id, disk_id_1)
attach_disk(cpi, instance_id, disk_id_2)

detach_disk(cpi, instance_id, disk_id_1)
detach_disk(cpi, instance_id, disk_id_2)

delete_disk(cpi, disk_id_1)
delete_disk(cpi, disk_id_2)

delete_vm(cpi, instance_id)

# 3. migrate: unmanaged v24 -> managed vNext

# 3.1 create resources using cpi v24
cpi = get_cpi(@upstream_repo, 'v24', false)

resource_pool = {
  'instance_type' => 'Standard_F2',
  'assign_dynamic_public_ip' => true,
  'availability_set' => 'unmanaged-avset',
  'storage_account_name' => @vm_storage_account_name,
  'storage_account_type' => 'Standard_LRS'
}

instance_id = create_vm(cpi, resource_pool)
disk_id_1 = create_disk(cpi, instance_id: instance_id)
disk_id_2 = create_disk(cpi, instance_id: nil)
attach_disk(cpi, instance_id, disk_id_1)
attach_disk(cpi, instance_id, disk_id_2)

# 3.2 check and delete resources using new cpi
cpi = get_cpi(@test_repo, @test_branch, true)

check_vm(cpi, instance_id)
check_disk(cpi, disk_id_1, instance_id: instance_id)
check_disk(cpi, disk_id_2, instance_id: instance_id)

detach_disk(cpi, instance_id, disk_id_1)
detach_disk(cpi, instance_id, disk_id_2)

attach_disk(cpi, instance_id, disk_id_1)
attach_disk(cpi, instance_id, disk_id_2)

detach_disk(cpi, instance_id, disk_id_1)
detach_disk(cpi, instance_id, disk_id_2)

delete_disk(cpi, disk_id_1)
delete_disk(cpi, disk_id_2)

delete_vm(cpi, instance_id)

# 4. attach v24 unmanaged disk to vNext unmanaged vm
# 4.1 create resources using cpi v24
cpi = get_cpi(@upstream_repo, 'v24', false)

resource_pool = {
  'instance_type' => 'Standard_F2',
  'assign_dynamic_public_ip' => true,
  'availability_set' => 'unmanaged-avset',
  'storage_account_name' => @vm_storage_account_name,
  'storage_account_type' => 'Standard_LRS'
}

instance_id = create_vm(cpi, resource_pool)
disk_id_1 = create_disk(cpi, instance_id: instance_id)
disk_id_2 = create_disk(cpi, instance_id: nil)

delete_vm(cpi, instance_id)

# 4.2 check if the disks created by v24 is workable with the vm created by vNext
cpi = get_cpi(@test_repo, @test_branch, false)

resource_pool = {
  'instance_type' => 'Standard_F2',
  'assign_dynamic_public_ip' => true,
  'availability_set' => 'unmanaged-avset',
  'storage_account_name' => @vm_storage_account_name,
  'storage_account_type' => 'Standard_LRS',
  'resource_group_name' => @additional_rg_name
}

instance_id = create_vm(cpi, resource_pool)

attach_disk(cpi, instance_id, disk_id_1)
attach_disk(cpi, instance_id, disk_id_2)

check_disk(cpi, disk_id_1, instance_id: instance_id)
check_disk(cpi, disk_id_2, instance_id: instance_id)

detach_disk(cpi, instance_id, disk_id_1)
detach_disk(cpi, instance_id, disk_id_2)

delete_disk(cpi, disk_id_1)
delete_disk(cpi, disk_id_2)

delete_vm(cpi, instance_id)

# 5. attach v24 managed disk to vNext managed vm
# 5.1 create resources using cpi v24
cpi = get_cpi(@upstream_repo, 'v24', true)

resource_pool = {
  'instance_type' => 'Standard_F2',
  'assign_dynamic_public_ip' => true,
  'availability_set' => 'managed-avset'
}

instance_id = create_vm(cpi, resource_pool)
disk_id_1 = create_disk(cpi, instance_id: instance_id)
disk_id_2 = create_disk(cpi, instance_id: nil)

delete_vm(cpi, instance_id)

# 5.2 check if the disks created by v24 is workable with the vm created by vNext
cpi = get_cpi(@test_repo, @test_branch, true)

resource_pool = {
  'instance_type' => 'Standard_F2',
  'assign_dynamic_public_ip' => true,
  'availability_set' => 'managed-avset',
  'resource_group_name' => @additional_rg_name
}

instance_id = create_vm(cpi, resource_pool)

attach_disk(cpi, instance_id, disk_id_1)
attach_disk(cpi, instance_id, disk_id_2)

check_disk(cpi, disk_id_1, instance_id: instance_id)
check_disk(cpi, disk_id_2, instance_id: instance_id)

detach_disk(cpi, instance_id, disk_id_1)
detach_disk(cpi, instance_id, disk_id_2)

delete_disk(cpi, disk_id_1)
delete_disk(cpi, disk_id_2)

delete_vm(cpi, instance_id)

# 6. attach v24 unmanaged disk to vNext managed vm
# 6.1 create resources using cpi v24
cpi = get_cpi(@upstream_repo, 'v24', false)

resource_pool = {
  'instance_type' => 'Standard_F2',
  'assign_dynamic_public_ip' => true,
  'availability_set' => 'unmanaged-avset',
  'storage_account_name' => @vm_storage_account_name,
  'storage_account_type' => 'Standard_LRS'
}

instance_id = create_vm(cpi, resource_pool)
disk_id_1 = create_disk(cpi, instance_id: instance_id)
disk_id_2 = create_disk(cpi, instance_id: nil)

delete_vm(cpi, instance_id)

# 6.2 check if the disks created by v24 is workable with the vm created by vNext
cpi = get_cpi(@test_repo, @test_branch, true)

resource_pool = {
  'instance_type' => 'Standard_F2',
  'assign_dynamic_public_ip' => true,
  'availability_set' => 'managed-avset',
  'resource_group_name' => @additional_rg_name
}

instance_id = create_vm(cpi, resource_pool)

attach_disk(cpi, instance_id, disk_id_1)
attach_disk(cpi, instance_id, disk_id_2)

check_disk(cpi, disk_id_1, instance_id: instance_id)
check_disk(cpi, disk_id_2, instance_id: instance_id)

detach_disk(cpi, instance_id, disk_id_1)
detach_disk(cpi, instance_id, disk_id_2)

delete_disk(cpi, disk_id_1)
delete_disk(cpi, disk_id_2)

delete_vm(cpi, instance_id)

# 7. attach a migrated disk (v21 unmanaged to v24 managed) to vNext managed vm
# 7.1 create resources using cpi v21
cpi = get_cpi(@upstream_repo, 'v21', false)

resource_pool = {
  'instance_type' => 'Standard_F2',
  'assign_dynamic_public_ip' => true,
  'availability_set' => 'unmanaged-avset',
  'storage_account_name' => @vm_storage_account_name,
  'storage_account_type' => 'Standard_LRS'
}

instance_id = create_vm(cpi, resource_pool)
disk_id_1 = create_disk(cpi, instance_id: instance_id)
disk_id_2 = create_disk(cpi, instance_id: nil)

delete_vm(cpi, instance_id)

# 7.2 migrate v21 unmanaged disk to v24 managed disk
cpi = get_cpi(@upstream_repo, 'v24', true)

resource_pool = {
  'instance_type' => 'Standard_F2',
  'assign_dynamic_public_ip' => true,
  'availability_set' => 'managed-avset'
}

instance_id = create_vm(cpi, resource_pool)

attach_disk(cpi, instance_id, disk_id_1) # migrate disk_id_x to managed disk
attach_disk(cpi, instance_id, disk_id_2)

check_disk(cpi, disk_id_1, instance_id: instance_id)
check_disk(cpi, disk_id_2, instance_id: instance_id)

detach_disk(cpi, instance_id, disk_id_1)
detach_disk(cpi, instance_id, disk_id_2)

delete_vm(cpi, instance_id)

# 7.3 check if the migrated disks are workable with the vm created by vNext
cpi = get_cpi(@test_repo, @test_branch, true)

resource_pool = {
  'instance_type' => 'Standard_F2',
  'assign_dynamic_public_ip' => true,
  'availability_set' => 'managed-avset',
  'resource_group_name' => @additional_rg_name
}

instance_id = create_vm(cpi, resource_pool)

attach_disk(cpi, instance_id, disk_id_1)
attach_disk(cpi, instance_id, disk_id_2)

check_disk(cpi, disk_id_1, instance_id: instance_id)
check_disk(cpi, disk_id_2, instance_id: instance_id)

detach_disk(cpi, instance_id, disk_id_1)
detach_disk(cpi, instance_id, disk_id_2)

delete_disk(cpi, disk_id_1)
delete_disk(cpi, disk_id_2)

delete_vm(cpi, instance_id)

# 8. attach vNext unmanged disk to v24 unmanaged vm
# 8.1 create resources using cpi v24
cpi = get_cpi(@upstream_repo, 'v24', false)

resource_pool = {
  'instance_type' => 'Standard_F2',
  'assign_dynamic_public_ip' => true,
  'availability_set' => 'unmanaged-avset',
  'storage_account_name' => @vm_storage_account_name,
  'storage_account_type' => 'Standard_LRS',
  'resource_group_name' => @additional_rg_name
}

instance_id = create_vm(cpi, resource_pool)

# 8.2 check if the disks created by vNext is workable with the vm created by v24
cpi = get_cpi(@test_repo, @test_branch, false)

disk_id_1 = create_disk(cpi, instance_id: instance_id)
disk_id_2 = create_disk(cpi, instance_id: nil)

attach_disk(cpi, instance_id, disk_id_1)
attach_disk(cpi, instance_id, disk_id_2)

check_disk(cpi, disk_id_1, instance_id: instance_id)
check_disk(cpi, disk_id_2, instance_id: instance_id)

detach_disk(cpi, instance_id, disk_id_1)
detach_disk(cpi, instance_id, disk_id_2)

delete_disk(cpi, disk_id_1)
delete_disk(cpi, disk_id_2)

delete_vm(cpi, instance_id)

# 9. attach vNext managed disk to v24 managed vm
# 9.1 create resources using cpi vNext
cpi = get_cpi(@upstream_repo, 'v24', true)

resource_pool = {
  'instance_type' => 'Standard_F2',
  'assign_dynamic_public_ip' => true,
  'availability_set' => 'managed-avset',
  'resource_group_name' => @additional_rg_name
}

instance_id = create_vm(cpi, resource_pool)

# 9.2 check if the disks created by vNext is workable with the vm created by v24
cpi = get_cpi(@test_repo, @test_branch, true)

disk_id_1 = create_disk(cpi, instance_id: instance_id)
disk_id_2 = create_disk(cpi, instance_id: nil)

attach_disk(cpi, instance_id, disk_id_1)
attach_disk(cpi, instance_id, disk_id_2)

check_disk(cpi, disk_id_1, instance_id: instance_id)
check_disk(cpi, disk_id_2, instance_id: instance_id)

detach_disk(cpi, instance_id, disk_id_1)
detach_disk(cpi, instance_id, disk_id_2)

delete_disk(cpi, disk_id_1)
delete_disk(cpi, disk_id_2)

delete_vm(cpi, instance_id)

# 10. migrate: unmanaged vNext -> managed vNext

# 10.1 create unmanaged resources
cpi = get_cpi(@test_repo, @test_branch, false)

resource_pool = {
  'instance_type' => 'Standard_F2',
  'assign_dynamic_public_ip' => true,
  'availability_set' => 'unmanaged-avset',
  'storage_account_name' => @vm_storage_account_name,
  'storage_account_type' => 'Standard_LRS',
  'resource_group_name' => @additional_rg_name
}

instance_id = create_vm(cpi, resource_pool)
disk_id_1 = create_disk(cpi, instance_id: instance_id)
disk_id_2 = create_disk(cpi, instance_id: nil)
attach_disk(cpi, instance_id, disk_id_1)
attach_disk(cpi, instance_id, disk_id_2)

# 10.2 check and delete vm
cpi = get_cpi(@test_repo, @test_branch, true)

check_vm(cpi, instance_id)
check_disk(cpi, disk_id_1, instance_id: instance_id)
check_disk(cpi, disk_id_2, instance_id: instance_id)

detach_disk(cpi, instance_id, disk_id_1)
detach_disk(cpi, instance_id, disk_id_2)

delete_vm(cpi, instance_id)

# 10.3 create new managed vm and attach existed disk to it.
resource_pool = {
  'instance_type' => 'Standard_F2',
  'assign_dynamic_public_ip' => true,
  'availability_set' => 'managed-avset',
  'resource_group_name' => @additional_rg_name
}

instance_id = create_vm(cpi, resource_pool)

attach_disk(cpi, instance_id, disk_id_1)
attach_disk(cpi, instance_id, disk_id_2)

detach_disk(cpi, instance_id, disk_id_1)
detach_disk(cpi, instance_id, disk_id_2)

delete_disk(cpi, disk_id_1)
delete_disk(cpi, disk_id_2)

delete_vm(cpi, instance_id)

puts 'PASS'
