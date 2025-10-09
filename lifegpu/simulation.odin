package lifegpu

import "core:log"
import "core:time"
import vk "vendor:vulkan"

SIMULATION_SHADER_BIN :: "shaders/bin/simulation.spv"
WORKGROUP_SIZE :: 16

g_last_sim_update: time.Tick

g_compute_cmd_pool: vk.CommandPool
g_compute_cmd_buffer: vk.CommandBuffer
g_compute_fence: vk.Fence
g_compute_tick_idx: u32 = 0

g_compute_pipeline_layout: vk.PipelineLayout
g_compute_pipeline: vk.Pipeline

ComputeConstants :: struct {
	readTexture:  u32,
	writeTexture: u32,
	tickIndex:    u32,
	randomize:    b32,
}

create_simulation :: proc() {
	cmd_pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = g_queue_family_indexes.graphics,
	}
	vk_try(vk.CreateCommandPool(g_device, &cmd_pool_info, nil, &g_compute_cmd_pool))
	cmd_buffer_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = g_compute_cmd_pool,
		commandBufferCount = 1,
	}
	vk_try(vk.AllocateCommandBuffers(g_device, &cmd_buffer_info, &g_compute_cmd_buffer))
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}
	vk_try(vk.CreateFence(g_device, &fence_info, nil, &g_compute_fence))
	create_pipeline()
}

destroy_simulation :: proc() {
	destroy_pipeline()
	vk.DestroyFence(g_device, g_compute_fence, nil)
	vk.DestroyCommandPool(g_device, g_compute_cmd_pool, nil)
}

@(private = "file")
record_commands :: proc(randomize: bool) {
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	vk.BeginCommandBuffer(g_compute_cmd_buffer, &begin_info)

	write_image := g_field_buffers[g_next_field].image
	transition_image_layout(
		g_compute_cmd_buffer,
		write_image,
		.GENERAL,
		.GENERAL,
		{.SHADER_READ},
		{.SHADER_WRITE},
		{.FRAGMENT_SHADER, .COMPUTE_SHADER},
		{.COMPUTE_SHADER},
		{.COLOR},
	)

	vk.CmdBindPipeline(g_compute_cmd_buffer, .COMPUTE, g_compute_pipeline)

	constants := ComputeConstants {
		readTexture  = u32(g_curr_field),
		writeTexture = u32(g_next_field),
		tickIndex    = g_compute_tick_idx,
		randomize    = b32(randomize),
	}
	vk.CmdPushConstants(
		g_compute_cmd_buffer,
		g_compute_pipeline_layout,
		{.COMPUTE},
		0,
		size_of(ComputeConstants),
		&constants,
	)
	vk.CmdBindDescriptorSets(
		g_compute_cmd_buffer,
		.COMPUTE,
		g_compute_pipeline_layout,
		0,
		1,
		&g_descriptor_set,
		0,
		nil,
	)
	vk.CmdDispatch(
		g_compute_cmd_buffer,
		FIELD_WIDTH / WORKGROUP_SIZE,
		FIELD_HEIGHT / WORKGROUP_SIZE,
		1,
	)

	transition_image_layout(
		g_compute_cmd_buffer,
		write_image,
		.GENERAL,
		.GENERAL,
		{.SHADER_WRITE},
		{.SHADER_READ},
		{.COMPUTE_SHADER},
		{.FRAGMENT_SHADER, .COMPUTE_SHADER},
		{.COLOR},
	)

	vk.EndCommandBuffer(g_compute_cmd_buffer)
}

simulate :: proc(randomize: bool) {
	vk_try(vk.WaitForFences(g_device, 1, &g_compute_fence, true, max(u64)))
	step_buffers()
	g_last_sim_update = time.tick_now()
	g_compute_tick_idx += 1

	vk.ResetCommandBuffer(g_compute_cmd_buffer, {})
	record_commands(randomize)

	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &g_compute_cmd_buffer,
	}

	vk.ResetFences(g_device, 1, &g_compute_fence)
	vk_try(vk.QueueSubmit(g_graphics_queue, 1, &submit_info, g_compute_fence))
}

reload_simulation :: proc() {
	vk.QueueWaitIdle(g_graphics_queue)
	destroy_pipeline()
	create_pipeline()
}

@(private = "file")
create_pipeline :: proc() {
	push_ranges := []vk.PushConstantRange {
		{stageFlags = {.COMPUTE}, offset = 0, size = size_of(ComputeConstants)},
	}
	compute_layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = raw_data(push_ranges),
		setLayoutCount         = 1,
		pSetLayouts            = &g_descriptor_set_layout,
	}
	vk_try(
		vk.CreatePipelineLayout(g_device, &compute_layout_info, nil, &g_compute_pipeline_layout),
	)

	module, success := load_shaders_from_file(SIMULATION_SHADER_BIN)
	if !success {
		log.panic("Failed to load compute shaders. Does file exists?")
	}
	compute_shader_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		module = module,
		stage  = {.COMPUTE},
		pName  = "main",
	}
	compute_pipeline_info := vk.ComputePipelineCreateInfo {
		sType  = .COMPUTE_PIPELINE_CREATE_INFO,
		stage  = compute_shader_info,
		layout = g_compute_pipeline_layout,
	}
	vk_try(
		vk.CreateComputePipelines(
			g_device,
			{},
			1,
			&compute_pipeline_info,
			nil,
			&g_compute_pipeline,
		),
	)

	vk.DestroyShaderModule(g_device, module, nil)
}

@(private = "file")
destroy_pipeline :: proc() {
	vk.DestroyPipelineLayout(g_device, g_compute_pipeline_layout, nil)
	vk.DestroyPipeline(g_device, g_compute_pipeline, nil)
}
