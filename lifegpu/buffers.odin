package lifegpu

import "core:sync"
import vk "vendor:vulkan"

FIELD_WIDTH :: 512
FIELD_HEIGHT :: 512
FIELD_BUFFER_COUNT :: 4

FieldBuffer :: struct {
	image:       vk.Image,
	memory:      vk.DeviceMemory,
	view:        vk.ImageView,
}

g_field_buffers: [FIELD_BUFFER_COUNT]FieldBuffer

g_prev_field := 0
g_curr_field := 1
g_next_field := 2

step_buffers :: proc() {
	g_prev_field = (g_prev_field + 1) % FIELD_BUFFER_COUNT
	g_curr_field = (g_curr_field + 1) % FIELD_BUFFER_COUNT
	g_next_field = (g_next_field + 1) % FIELD_BUFFER_COUNT
}

create_buffers :: proc() {
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	vk.BeginCommandBuffer(g_base_cmd_buffer, &begin_info)
	for i in 0 ..< FIELD_BUFFER_COUNT {
		g_field_buffers[i] = create_field_buffer()
	}
	vk.EndCommandBuffer(g_base_cmd_buffer)
	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		waitSemaphoreCount = 0,
		commandBufferCount = 1,
		pCommandBuffers    = &g_base_cmd_buffer,
	}
	vk_try(vk.QueueSubmit(g_graphics_queue, 1, &submit_info, {}))
	vk_try(vk.QueueWaitIdle(g_graphics_queue))

	image_infos: [FIELD_BUFFER_COUNT]vk.DescriptorImageInfo
	for i in 0 ..< FIELD_BUFFER_COUNT {
		image_infos[i] = vk.DescriptorImageInfo {
			imageView   = g_field_buffers[i].view,
			imageLayout = .GENERAL,
		}
	}
	desc_write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = g_descriptor_set,
		dstBinding      = 0,
		dstArrayElement = 0,
		descriptorCount = FIELD_BUFFER_COUNT,
		descriptorType  = .STORAGE_IMAGE,
		pImageInfo      = &image_infos[0],
	}
	vk.UpdateDescriptorSets(g_device, 1, &desc_write, 0, nil)
}

destroy_buffers :: proc() {
	for i in 0 ..< FIELD_BUFFER_COUNT {
		destroy_field_buffer(g_field_buffers[i])
	}
}

@(private = "file")
create_field_buffer :: proc() -> (buf: FieldBuffer) {
	image, mem := create_2d_image(
		.R32G32_UINT,
		FIELD_WIDTH,
		FIELD_HEIGHT,
		{.STORAGE},
		.UNDEFINED,
	)
	transition_image_layout(
		g_base_cmd_buffer,
		image,
		.UNDEFINED,
		.GENERAL,
		{},
		{.SHADER_READ},
		{.TOP_OF_PIPE},
		{.FRAGMENT_SHADER, .COMPUTE_SHADER},
		{.COLOR},
	)
	create_view_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = image,
		viewType = .D2,
		format = .R32G32_UINT,
		subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
	}
	buf.image = image
	buf.memory = mem
	vk_try(vk.CreateImageView(g_device, &create_view_info, nil, &buf.view))
	return
}

@(private = "file")
destroy_field_buffer :: proc(buf: FieldBuffer) {
	vk.DestroyImageView(g_device, buf.view, nil)
	vk.DestroyImage(g_device, buf.image, nil)
	vk.FreeMemory(g_device, buf.memory, nil)
}
