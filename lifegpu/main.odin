package lifegpu

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import "core:os/os2"
import "core:slice"
import "core:strings"
import "core:thread"
import "core:time"

import glfw "vendor:glfw"
import vk "vendor:vulkan"

g_context: runtime.Context
g_window: glfw.WindowHandle
g_window_resized := false

g_recompiling_shaders := false
g_should_reload_shaders := false

g_camera: Camera = {
	x = 0,
	y = 0,
	z = 0.5,
}

InputState :: struct {
	x_movement:  f32,
	y_movement:  f32,
	z_movement:  f32,
	hspeed:      f32,
	vspeed:      f32,
	rnd_pressed: b32,
}
g_input: InputState = {
	hspeed = 1.8,
	vspeed = 3,
}

SIMULATE_EVERY_N_FRAMES :: 10

main :: proc() {
	context.logger = log.create_console_logger()
	g_context = context
	if !glfw.Init() {
		log.panicf("Failed to initialize glfw")
	}
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	g_window = glfw.CreateWindow(800, 600, "lifegpu", nil, nil)
	if g_window == nil {
		log.panicf("Failed to create window")
	}
	defer glfw.DestroyWindow(g_window)
	glfw.SetFramebufferSizeCallback(g_window, proc "c" (_: glfw.WindowHandle, _, _: i32) {
		context = g_context
		g_window_resized = true
	})
	glfw.SetScrollCallback(g_window, on_scroll)
	glfw.SetKeyCallback(g_window, on_input)

	create()
	defer destroy()

	last_tick := time.tick_now()
	frame_index := 0
	for !glfw.WindowShouldClose(g_window) {
		glfw.PollEvents()
		if g_should_reload_shaders {
			reload_renderer()
			reload_simulation()
			g_should_reload_shaders = false
		}
		current_tick := time.tick_now()
		tick_delta := f32(time.duration_seconds(time.tick_diff(last_tick, current_tick)))
		last_tick = current_tick
		g_camera.z = g_camera.z * math.pow(g_input.vspeed, g_input.z_movement * tick_delta)
		h_speed_factor := (g_camera.z + MIN_SCALE)
		g_camera.x += g_input.x_movement * g_input.hspeed * h_speed_factor * tick_delta
		g_camera.y += g_input.y_movement * g_input.hspeed * h_speed_factor * tick_delta
		render(g_camera)
		if g_input.rnd_pressed {
			simulate(true)
			g_input.rnd_pressed = false
		}
		if frame_index % SIMULATE_EVERY_N_FRAMES == 0 {
			simulate(false)
		}
		frame_index += 1
	}

	vk.DeviceWaitIdle(g_device)
}

@(private = "file")
create :: proc() {
	create_vulkan()
	create_descriptors()
	create_buffers()
	create_renderer()
	create_simulation()
}

@(private = "file")
destroy :: proc() {
	destroy_simulation()
	destroy_renderer()
	destroy_buffers()
	destroy_descriptors()
	destroy_vulkan()
}

@(private = "file")
on_input :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	context = g_context
	if action == glfw.PRESS {
		switch key {
		case glfw.KEY_C:
			{
				recompile_shaders()
			}
		case glfw.KEY_R:
			{
				g_camera.x = 0
				g_camera.y = 0
				g_camera.z = 0.5
			}
		case glfw.KEY_F:
			{
				g_input.rnd_pressed = true
			}
		}
	}
	if action == glfw.REPEAT {
		return
	}
	factor: f32 = 1 if action == glfw.PRESS else -1
	switch key {
	case glfw.KEY_W:
		{
			g_input.y_movement -= factor
		}
	case glfw.KEY_S:
		{
			g_input.y_movement += factor
		}
	case glfw.KEY_D:
		{
			g_input.x_movement += factor
		}
	case glfw.KEY_A:
		{
			g_input.x_movement -= factor
		}
	case glfw.KEY_LEFT_SHIFT:
		{
			g_input.z_movement -= factor
		}
	case glfw.KEY_SPACE:
		{
			g_input.z_movement += factor
		}
	}
}

@(private = "file")
on_scroll :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	context = g_context

}

@(private = "file")
recompile_shaders :: proc() {
	if g_recompiling_shaders {
		return
	}
	log.info("Recompiling shaders")
	g_recompiling_shaders = true

	call_compiler_thread :: proc() {
		context = g_context
		desc := os2.Process_Desc {
			working_dir = "shaders",
			command     = []string{"bash", "compile.sh"},
		}
		state, stdout, stderr, err := os2.process_exec(desc, g_context.allocator)
		log.info(strings.truncate_to_byte(string(stdout), 0))
		log.info(strings.truncate_to_byte(string(stderr), 0))
		log.infof("Compiler exited with code %d", state.exit_code)
		g_recompiling_shaders = false
		if state.exit_code == 0 {
			g_should_reload_shaders = true
		}
	}
	thread.create_and_start(call_compiler_thread)
}
