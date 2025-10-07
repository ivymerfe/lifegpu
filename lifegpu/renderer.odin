package lifegpu

import "core:log"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/glsl"
import "core:mem"
import "core:sync"
import "core:time"
import vk "vendor:vulkan"

RENDERING_SHADER_BIN :: "shaders/bin/rendering.spv"
QUAD_VERTICES :: 6
MIN_SCALE :: 0.001

g_descriptor_set_layout: vk.DescriptorSetLayout
g_descriptor_pool: vk.DescriptorPool
g_descriptor_set: vk.DescriptorSet
g_pipeline: vk.Pipeline
g_pipeline_layout: vk.PipelineLayout

Camera :: struct {
	x: f32,
	y: f32,
	z: f32,
}

SceneConstants :: struct {
	x:            f32,
	y:            f32,
	scale:        f32,
	aspect_ratio: f32,
	prev_texture: u32,
	curr_texture: u32,
	delta:        f32,
}

init_renderer :: proc() {
	create_descriptors()
	create_pipeline()
}

destroy_renderer :: proc() {
	destroy_pipeline()
	destroy_descriptors()
}

get_scene_constants :: proc(
	camera: Camera,
	prev_idx, curr_idx: int,
	time_delta: f32,
) -> SceneConstants {
	return SceneConstants {
		x = camera.x,
		y = camera.y,
		scale = 1 / (camera.z + MIN_SCALE),
		aspect_ratio = f32(g_swapchain_extent.width) / f32(g_swapchain_extent.height),
		prev_texture = u32(prev_idx),
		curr_texture = u32(curr_idx),
		delta = time_delta,
	}
}

record_commands :: proc(camera: Camera, image_index: u32, prev_texture, curr_texture: int) {
	cmd_buffer := g_command_buffer
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	vk.BeginCommandBuffer(cmd_buffer, &begin_info)

	current_image := g_swapchain_images[image_index]
	transition_image_layout(
		cmd_buffer,
		current_image,
		.UNDEFINED,
		.COLOR_ATTACHMENT_OPTIMAL,
		{},
		{.COLOR_ATTACHMENT_WRITE},
		{.TOP_OF_PIPE},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR},
	)
	clear_color := vk.ClearValue {
		color = {float32 = [4]f32{0.2, 0.2, 0.2, 1}},
	}
	color_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = g_swapchain_image_views[image_index],
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .STORE,
		clearValue  = clear_color,
	}
	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {offset = {0, 0}, extent = g_swapchain_extent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment,
	}
	vk.CmdBeginRendering(cmd_buffer, &rendering_info)
	vk.CmdBindPipeline(cmd_buffer, .GRAPHICS, g_pipeline)
	vk.CmdSetViewport(
		cmd_buffer,
		0,
		1,
		&vk.Viewport {
			x = 0,
			y = 0,
			width = auto_cast g_swapchain_extent.width,
			height = auto_cast g_swapchain_extent.height,
			minDepth = 0,
			maxDepth = 1,
		},
	)
	vk.CmdSetScissor(cmd_buffer, 0, 1, &vk.Rect2D{offset = {0, 0}, extent = g_swapchain_extent})

	time_delta := f32(time.duration_seconds(time.tick_diff(g_last_sim_update, time.tick_now())))
	constants := get_scene_constants(camera, prev_texture, curr_texture, time_delta)
	vk.CmdPushConstants(
		cmd_buffer,
		g_pipeline_layout,
		{.VERTEX, .FRAGMENT},
		0,
		size_of(SceneConstants),
		&constants,
	)
	vk.CmdBindDescriptorSets(
		cmd_buffer,
		.GRAPHICS,
		g_pipeline_layout,
		0,
		1,
		&g_descriptor_set,
		0,
		nil,
	)
	vk.CmdDraw(cmd_buffer, QUAD_VERTICES, 1, 0, 0)
	vk.CmdEndRendering(cmd_buffer)
	transition_image_layout(
		cmd_buffer,
		current_image,
		.COLOR_ATTACHMENT_OPTIMAL,
		.PRESENT_SRC_KHR,
		{.COLOR_ATTACHMENT_WRITE},
		{},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.BOTTOM_OF_PIPE},
		{.COLOR},
	)
	vk.EndCommandBuffer(cmd_buffer)
}

render :: proc(camera: Camera) {
	sem_image_available := g_image_available_semaphore
	fence_acquire := g_acquire_fence

	vk_try(vk.ResetFences(g_device, 1, &fence_acquire))

	image_index: u32
	acquire_result := vk.AcquireNextImageKHR(
		g_device,
		g_swapchain,
		0,
		sem_image_available,
		fence_acquire,
		&image_index,
	)
	#partial switch acquire_result {
	case .ERROR_OUT_OF_DATE_KHR:
		recreate_swapchain()
		return
	case .SUCCESS, .SUBOPTIMAL_KHR:
	case:
		log.panicf("vulkan: acquire next image failure: %v", acquire_result)
	}
	vk_try(vk.WaitForFences(g_device, 1, &fence_acquire, true, max(u64)))

	cmd_buffer := g_command_buffer
	vk.ResetCommandBuffer(cmd_buffer, {})

	curr_texture := acquire_buffer_read()
	prev_texture := acquire_buffer_read(curr_texture)
	if curr_texture == -1 || prev_texture == -1 {
		panic("No free buffers for renderer! Should not happen")
	}
	record_commands(camera, image_index, prev_texture, curr_texture)

	sem_render_finished := g_render_finished_semaphore[image_index]
	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &sem_image_available,
		pWaitDstStageMask    = &vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT},
		commandBufferCount   = 1,
		pCommandBuffers      = &cmd_buffer,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &sem_render_finished,
	}

	vk_try(vk.ResetFences(g_device, 1, &g_render_fence))

	sync.lock(&g_graphics_queue_lock)
	vk_try(vk.QueueSubmit(g_graphics_queue, 1, &submit_info, g_render_fence))
	sync.unlock(&g_graphics_queue_lock)

	vk_try(vk.WaitForFences(g_device, 1, &g_render_fence, true, max(u64)))

	release_buffer(prev_texture)
	release_buffer(curr_texture)

	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &sem_render_finished,
		swapchainCount     = 1,
		pSwapchains        = &g_swapchain,
		pImageIndices      = &image_index,
	}
	present_result := vk.QueuePresentKHR(g_present_queue, &present_info)
	switch {
	case present_result == .ERROR_OUT_OF_DATE_KHR ||
	     present_result == .SUBOPTIMAL_KHR ||
	     g_window_resized:
		g_window_resized = false
		recreate_swapchain()
	case present_result == .SUCCESS:
	case:
		log.panicf("vulkan: present failure: %v", present_result)
	}
}

@(private = "file")
create_descriptors :: proc() {
	tex_binding := vk.DescriptorSetLayoutBinding {
		binding         = 0,
		descriptorType  = .SAMPLED_IMAGE,
		descriptorCount = FIELD_BUFFER_COUNT,
		stageFlags      = {.FRAGMENT},
	}
	create_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 1,
		pBindings    = &tex_binding,
	}
	vk_try(vk.CreateDescriptorSetLayout(g_device, &create_info, nil, &g_descriptor_set_layout))
	pool_size := vk.DescriptorPoolSize {
		type            = .SAMPLED_IMAGE,
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

@(private = "file")
destroy_descriptors :: proc() {
	vk_try(vk.FreeDescriptorSets(g_device, g_descriptor_pool, 1, &g_descriptor_set))
	vk.DestroyDescriptorPool(g_device, g_descriptor_pool, nil)
	vk.DestroyDescriptorSetLayout(g_device, g_descriptor_set_layout, nil)
}

reload_renderer :: proc() {
	vk.QueueWaitIdle(g_graphics_queue)
	destroy_pipeline()
	create_pipeline()
}

@(private = "file")
create_pipeline :: proc() {
	push_constant_ranges := []vk.PushConstantRange {
		{stageFlags = {.VERTEX, .FRAGMENT}, offset = 0, size = size_of(SceneConstants)},
	}
	layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = raw_data(push_constant_ranges),
		setLayoutCount         = 1,
		pSetLayouts            = &g_descriptor_set_layout,
	}
	vk_try(vk.CreatePipelineLayout(g_device, &layout_info, nil, &g_pipeline_layout))

	dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates    = raw_data(dynamic_states),
	}
	vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	}
	input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
	}
	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}
	rasterizer := vk.PipelineRasterizationStateCreateInfo {
		sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		lineWidth   = 1,
		cullMode    = {.BACK},
		frontFace   = .CLOCKWISE,
	}
	multisampling := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
		minSampleShading     = 1,
	}
	color_blend_attachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask = {.R, .G, .B, .A},
	}
	color_blending := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &color_blend_attachment,
	}
	depth_stencil_state := vk.PipelineDepthStencilStateCreateInfo {
		sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable  = true,
		depthWriteEnable = true,
		depthCompareOp   = .LESS,
	}

	module, success := load_shaders_from_file(RENDERING_SHADER_BIN)
	if !success {
		log.panicf("Failed to load shaders, check if file exists")
	}
	vertex_shader_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.VERTEX},
		module = module,
		pName  = "vsMain",
	}
	pixel_shader_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.FRAGMENT},
		module = module,
		pName  = "psMain",
	}
	shader_stages := []vk.PipelineShaderStageCreateInfo{vertex_shader_info, pixel_shader_info}
	pipeline_rendering_info := vk.PipelineRenderingCreateInfo {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = 1,
		pColorAttachmentFormats = &g_swapchain_format.format,
		depthAttachmentFormat   = .D32_SFLOAT,
		stencilAttachmentFormat = .UNDEFINED,
	}
	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &pipeline_rendering_info,
		stageCount          = 2,
		pStages             = raw_data(shader_stages),
		pVertexInputState   = &vertex_input_info,
		pInputAssemblyState = &input_assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &rasterizer,
		pMultisampleState   = &multisampling,
		pColorBlendState    = &color_blending,
		pDynamicState       = &dynamic_state,
		pDepthStencilState  = &depth_stencil_state,
		layout              = g_pipeline_layout,
		subpass             = 0,
		basePipelineIndex   = -1,
	}
	vk_try(vk.CreateGraphicsPipelines(g_device, 0, 1, &pipeline_info, nil, &g_pipeline))

	vk.DestroyShaderModule(g_device, module, nil)
}

@(private = "file")
destroy_pipeline :: proc() {
	vk.DestroyPipelineLayout(g_device, g_pipeline_layout, nil)
	vk.DestroyPipeline(g_device, g_pipeline, nil)
}
