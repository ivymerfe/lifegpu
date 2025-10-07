package lifegpu

import "core:sync"
import "core:time"
import vk "vendor:vulkan"

SIMULATION_SHADER_BIN :: "shaders/bin/simulation.spv"

g_last_sim_update: time.Tick
g_prev_sim_texture: int = -1

ComputeConstants :: struct {
	readTexture:  u32,
	writeTexture: u32,
	currentTime:  f32,
	randomize:    b32,
}

init_simulation :: proc() {
	create_pipeline()
}

destroy_simulation :: proc() {
	destroy_pipeline()
}

simulate :: proc() {

	g_last_sim_update = time.tick_now()
}

reload_simulation :: proc() {
	vk.QueueWaitIdle(g_graphics_queue)
	destroy_pipeline()
	create_pipeline()
}

@(private = "file")
create_pipeline :: proc() {

}

@(private = "file")
destroy_pipeline :: proc() {

}
