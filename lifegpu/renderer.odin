package lifevk

import "core:log"
import "core:math"
import "core:math/linalg"
import "core:math/linalg/glsl"
import "core:mem"
import "core:time"
import vk "vendor:vulkan"

VIEWER_SHADER_FILE :: "shaders/bin/view.spv"
QUAD_VERTICES :: 6
MIN_SCALE :: 0.01

g_pipeline: vk.Pipeline
g_pipeline_layout: vk.PipelineLayout

Camera :: struct {
	x: f32,
	y: f32,
	z: f32
}

SceneConstants :: struct {
	x: f32,
	y: f32,
	scale: f32,
	aspect_ratio: f32
}

init_renderer :: proc() {
	create_pipeline()
	create_resources()
}

destroy_renderer :: proc() {
	destroy_resources()
	destroy_pipeline()
}

get_scene_constants :: proc(camera: Camera) -> SceneConstants {
	return SceneConstants{
		x = camera.x,
		y = camera.y,
		scale = 1 / (camera.z + MIN_SCALE),
		aspect_ratio = f32(g_swapchain_extent.width) / f32(g_swapchain_extent.height)
	}
}

record_commands :: proc(
	camera: Camera,
	cmd_buffer: vk.CommandBuffer,
	image_index: u32,
) {
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
		color = {float32 = [4]f32{0.2, 0.8, 0.1, 1}},
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

	constants := get_scene_constants(camera)
	vk.CmdPushConstants(
		cmd_buffer,
		g_pipeline_layout,
		{.VERTEX},
		0,
		size_of(SceneConstants),
		&constants,
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

@(private = "file")
create_resources :: proc() {
	
}

@(private = "file")
destroy_resources :: proc() {
	
}

recreate_pipeline :: proc() {
	vk.QueueWaitIdle(g_graphics_queue)
	destroy_pipeline()
	create_pipeline()
}

@(private = "file")
create_pipeline :: proc() {
	push_constant_ranges := []vk.PushConstantRange {
		{stageFlags = {.VERTEX}, offset = 0, size = size_of(SceneConstants)},
	}
	layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = raw_data(push_constant_ranges),
	}
	vk_try(vk.CreatePipelineLayout(g_device, &layout_info, nil, &g_pipeline_layout))

	dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates    = raw_data(dynamic_states),
	}
	vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
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

	module, success := load_shaders_from_file(VIEWER_SHADER_FILE)
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
