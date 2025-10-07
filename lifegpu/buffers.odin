package lifegpu

import "core:sync"
import vk "vendor:vulkan"

FIELD_WIDTH :: 512
FIELD_HEIGHT :: 512
FIELD_BUFFER_COUNT :: 4 // one free, two rendering (transition), one processing

BufferUsageType :: enum {
	NOT_USED,
	READING,
	WRITING,
}

FieldBuffer :: struct {
	image:       vk.Image,
	memory:      vk.DeviceMemory,
	view:        vk.ImageView,
	usage:       BufferUsageType,
	last_update: i64,
}

g_field_buffers: [FIELD_BUFFER_COUNT]FieldBuffer

buffer_lock: sync.Mutex

acquire_buffer_read :: proc(ignore_index: int = -1) -> int {
	sync.lock(&buffer_lock)
	defer sync.unlock(&buffer_lock)
	idx := -1
	upd: i64 = -1
	for i in 0 ..< FIELD_BUFFER_COUNT {
		if i == ignore_index {
			continue
		}
		if g_field_buffers[i].usage != .WRITING && g_field_buffers[i].last_update > upd {
			idx = i
			upd = g_field_buffers[i].last_update
		}
	}
	if idx != -1 {
		g_field_buffers[idx].usage = .READING
	}
	return idx
}

acquire_buffer_write :: proc() -> int {
	sync.lock(&buffer_lock)
	defer sync.unlock(&buffer_lock)
	idx := -1
	upd: i64 = -1
	for i in 0 ..< FIELD_BUFFER_COUNT {
		if g_field_buffers[i].usage != .WRITING && g_field_buffers[i].last_update > upd {
			idx = i
			upd = g_field_buffers[i].last_update
		}
	}
	if idx != -1 {
		g_field_buffers[idx].usage = .WRITING
	}
	return idx
}

release_buffer :: proc(buffer_index: int) {
	sync.lock(&buffer_lock)
	defer sync.unlock(&buffer_lock)
	if g_field_buffers[buffer_index].usage == .WRITING {
		g_field_buffers[buffer_index].last_update += 1
	}
	g_field_buffers[buffer_index].usage = .NOT_USED
}

init_buffers :: proc() {
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	vk.BeginCommandBuffer(g_command_buffer, &begin_info)
	for i in 0 ..< FIELD_BUFFER_COUNT {
		g_field_buffers[i] = create_field_buffer()
	}
	vk.EndCommandBuffer(g_command_buffer)
	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		waitSemaphoreCount = 0,
		commandBufferCount = 1,
		pCommandBuffers    = &g_command_buffer,
	}
	fence := g_render_fence
	vk_try(vk.ResetFences(g_device, 1, &fence))
	vk_try(vk.QueueSubmit(g_graphics_queue, 1, &submit_info, fence))
	vk_try(vk.WaitForFences(g_device, 1, &fence, true, max(u64)))

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
		descriptorType  = .SAMPLED_IMAGE,
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
		{.SAMPLED, .STORAGE},
		.UNDEFINED,
	)
	transition_image_layout(
		g_command_buffer,
		image,
		.UNDEFINED,
		.GENERAL,
		{},
		{.SHADER_READ},
		{.TOP_OF_PIPE},
		{.FRAGMENT_SHADER},
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
	buf.usage = .NOT_USED
	buf.last_update = 0
	vk_try(vk.CreateImageView(g_device, &create_view_info, nil, &buf.view))
	return
}

@(private = "file")
destroy_field_buffer :: proc(buf: FieldBuffer) {
	vk.DestroyImageView(g_device, buf.view, nil)
	vk.DestroyImage(g_device, buf.image, nil)
	vk.FreeMemory(g_device, buf.memory, nil)
}
