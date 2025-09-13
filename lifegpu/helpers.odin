package lifegpu

import "core:log"
import os "core:os"
import vk "vendor:vulkan"

load_shaders_from_file :: proc(filename: string) -> (vk.ShaderModule, bool) {
	bytes, success := os.read_entire_file(filename)
	if !success {
		return vk.ShaderModule{}, false
	}
	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(bytes),
		pCode    = auto_cast raw_data(bytes),
	}
	module: vk.ShaderModule
	result := vk.CreateShaderModule(g_device, &create_info, nil, &module)
	if result != .SUCCESS {
		return vk.ShaderModule{}, false
	}
	return module, true
}

transition_image_layout :: proc(
	command_buffer: vk.CommandBuffer,
	image: vk.Image,
	old_layout, new_layout: vk.ImageLayout,
	src_access_mask, dst_access_mask: vk.AccessFlags2,
	src_stage_mask, dst_stage_mask: vk.PipelineStageFlags2,
    aspect_mask: vk.ImageAspectFlags
) {
	barrier := vk.ImageMemoryBarrier2 {
		sType = .IMAGE_MEMORY_BARRIER_2,
		srcStageMask = src_stage_mask,
		srcAccessMask = src_access_mask,
		dstStageMask = dst_stage_mask,
		dstAccessMask = dst_access_mask,
		oldLayout = old_layout,
		newLayout = new_layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = {aspectMask = aspect_mask, levelCount = 1, layerCount = 1},
	}
	dependency_info := vk.DependencyInfo {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = &barrier,
	}
	vk.CmdPipelineBarrier2(command_buffer, &dependency_info)
}

find_memory_type :: proc(type_filter: u32, props: vk.MemoryPropertyFlags) -> (u32, bool) {
	for i in 0 ..< g_mem_properties.memoryTypeCount {
		if bool(type_filter & (1 << i)) && props <= g_mem_properties.memoryTypes[i].propertyFlags {
			return i, true
		}
	}
	return 0, false
}

try_allocate :: proc(
	mem_requirements: vk.MemoryRequirements,
	props: vk.MemoryPropertyFlags,
) -> (
	memory: vk.DeviceMemory,
) {
	mem_type, success := find_memory_type(mem_requirements.memoryTypeBits, props)
	if !success {
		log.panic("Failed to find memory type")
	}
	allocate_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_requirements.size,
		memoryTypeIndex = mem_type,
	}
	vk_try(vk.AllocateMemory(g_device, &allocate_info, nil, &memory))
	return
}

create_2d_image :: proc(
	format: vk.Format,
	width, height: u32,
	usage: vk.ImageUsageFlags,
	initialLayout: vk.ImageLayout,
) -> (
	image: vk.Image,
	mem: vk.DeviceMemory,
) {
	image_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		format = format,
		extent = {width = width, height = height, depth = 1},
		mipLevels = 1,
		arrayLayers = 1,
		samples = {._1},
		tiling = .OPTIMAL,
		usage = usage,
		initialLayout = initialLayout,
	}
	vk_try(vk.CreateImage(g_device, &image_info, nil, &image))
	mem_req: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(g_device, image, &mem_req)
	mem = try_allocate(mem_req, {.DEVICE_LOCAL})
	vk_try(vk.BindImageMemory(g_device, image, mem, 0))
    return
}
