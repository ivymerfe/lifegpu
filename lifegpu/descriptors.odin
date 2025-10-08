package lifegpu

import vk "vendor:vulkan"

g_descriptor_set_layout: vk.DescriptorSetLayout
g_descriptor_pool: vk.DescriptorPool
g_descriptor_set: vk.DescriptorSet


create_descriptors :: proc() {
	tex_binding := vk.DescriptorSetLayoutBinding {
		binding         = 0,
		descriptorType  = .STORAGE_IMAGE,
		descriptorCount = FIELD_BUFFER_COUNT,
		stageFlags      = {.FRAGMENT, .COMPUTE},
	}
	create_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 1,
		pBindings    = &tex_binding,
	}
	vk_try(vk.CreateDescriptorSetLayout(g_device, &create_info, nil, &g_descriptor_set_layout))
	pool_size := vk.DescriptorPoolSize {
		type            = .STORAGE_IMAGE,
		descriptorCount = FIELD_BUFFER_COUNT,
	}
	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		flags         = {.FREE_DESCRIPTOR_SET},
		maxSets       = 1,
		poolSizeCount = 1,
		pPoolSizes    = &pool_size,
	}
	vk_try(vk.CreateDescriptorPool(g_device, &pool_info, nil, &g_descriptor_pool))
	desc_set_alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = g_descriptor_pool,
		descriptorSetCount = 1,
		pSetLayouts        = &g_descriptor_set_layout,
	}
	vk_try(vk.AllocateDescriptorSets(g_device, &desc_set_alloc_info, &g_descriptor_set))
}

destroy_descriptors :: proc() {
	vk_try(vk.FreeDescriptorSets(g_device, g_descriptor_pool, 1, &g_descriptor_set))
	vk.DestroyDescriptorPool(g_device, g_descriptor_pool, nil)
	vk.DestroyDescriptorSetLayout(g_device, g_descriptor_set_layout, nil)
}
