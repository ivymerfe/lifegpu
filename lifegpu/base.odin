package lifegpu

import "base:runtime"
import "core:log"
import "core:slice"
import "core:time"
import "core:sync"
import glfw "vendor:glfw"
import vk "vendor:vulkan"

g_instance: vk.Instance
g_surface: vk.SurfaceKHR
g_physical_device: vk.PhysicalDevice
g_mem_properties: vk.PhysicalDeviceMemoryProperties
g_deviceName: string
g_device: vk.Device

g_graphics_queue: vk.Queue
g_present_queue: vk.Queue
g_graphics_queue_lock: sync.Mutex

QueueFamilyIdx :: struct {
	graphics: u32,
	present:  u32,
}

g_queue_family_indexes: QueueFamilyIdx

g_swapchain: vk.SwapchainKHR
g_swapchain_format: vk.SurfaceFormatKHR
g_swapchain_extent: vk.Extent2D
g_swapchain_image_count: u32
g_swapchain_images: []vk.Image
g_swapchain_image_views: []vk.ImageView

g_command_pool: vk.CommandPool

g_command_buffer: vk.CommandBuffer
g_image_available_semaphore: vk.Semaphore
g_render_finished_semaphore: []vk.Semaphore // Per image
g_render_fence: vk.Fence
g_acquire_fence: vk.Fence

vk_try :: proc(result: vk.Result, location := #caller_location) {
	if result != .SUCCESS {
		log.panicf("Vulkan failed with result = %v", result, location)
	}
}

init_vulkan :: proc() {
	vk_create_instance()

	vk_try(glfw.CreateWindowSurface(g_instance, g_window, nil, &g_surface))

	vk_pick_device()
	vk_create_logical_device()
	vk_create_swapchain()

	cmd_pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = g_queue_family_indexes.graphics,
	}
	vk_try(vk.CreateCommandPool(g_device, &cmd_pool_info, nil, &g_command_pool))

	cmd_buffer_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = g_command_pool,
		commandBufferCount = 1,
	}
	vk_try(vk.AllocateCommandBuffers(g_device, &cmd_buffer_info, &g_command_buffer))

	g_render_finished_semaphore = make([]vk.Semaphore, g_swapchain_image_count)
	sem_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}
	vk_try(vk.CreateSemaphore(g_device, &sem_info, nil, &g_image_available_semaphore))
	vk_try(vk.CreateFence(g_device, &fence_info, nil, &g_render_fence))
	vk_try(vk.CreateFence(g_device, &fence_info, nil, &g_acquire_fence))
	for i in 0 ..< g_swapchain_image_count {
		vk_try(vk.CreateSemaphore(g_device, &sem_info, nil, &g_render_finished_semaphore[i]))
	}

	log.info("Vulkan initialised")
}

destroy_vulkan :: proc() {
	vk.DestroySemaphore(g_device, g_image_available_semaphore, nil)
	vk.DestroyFence(g_device, g_render_fence, nil)
	vk.DestroyFence(g_device, g_acquire_fence, nil)

	for i in 0 ..< g_swapchain_image_count {
		vk.DestroySemaphore(g_device, g_render_finished_semaphore[i], nil)
	}
	delete(g_render_finished_semaphore)
	vk.DestroyCommandPool(g_device, g_command_pool, nil)

	vk_destroy_swapchain()
	vk.DestroyDevice(g_device, nil)
	vk.DestroySurfaceKHR(g_instance, g_surface, nil)
	vk.DestroyInstance(g_instance, nil)
}

@(private = "file")
vk_create_instance :: proc() {
	vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))
	if vk.CreateInstance == nil {
		log.panicf("Failed to load vulkan function pointers")
	}

	create_info := vk.InstanceCreateInfo {
		sType            = .INSTANCE_CREATE_INFO,
		pApplicationInfo = &vk.ApplicationInfo {
			sType = .APPLICATION_INFO,
			pApplicationName = "VSpace",
			applicationVersion = vk.MAKE_VERSION(1, 0, 0),
			pEngineName = "VSpace",
			engineVersion = vk.MAKE_VERSION(1, 0, 0),
			apiVersion = vk.API_VERSION_1_4,
		},
	}
	extensions := slice.clone_to_dynamic(
		glfw.GetRequiredInstanceExtensions(),
		context.temp_allocator,
	)
	when ENABLE_VALIDATION {
		create_info.ppEnabledLayerNames = raw_data([]cstring{"VK_LAYER_KHRONOS_validation"})
		create_info.enabledLayerCount = 1

		append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)

		// Severity based on logger level.
		severity: vk.DebugUtilsMessageSeverityFlagsEXT
		if context.logger.lowest_level <= .Error {
			severity |= {.ERROR}
		}
		if context.logger.lowest_level <= .Warning {
			severity |= {.WARNING}
		}
		if context.logger.lowest_level <= .Info {
			severity |= {.INFO}
		}
		if context.logger.lowest_level <= .Debug {
			severity |= {.VERBOSE}
		}

		dbg_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
			sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = severity,
			messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE}, // all of them.
			pfnUserCallback = vk_messenger_callback,
		}
		create_info.pNext = &dbg_create_info
	}
	create_info.enabledExtensionCount = u32(len(extensions))
	create_info.ppEnabledExtensionNames = raw_data(extensions)

	vk_try(vk.CreateInstance(&create_info, nil, &g_instance))
	vk.load_proc_addresses_instance(g_instance)
}

@(private = "file")
vk_messenger_callback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = g_context

	level: log.Level
	if .ERROR in messageSeverity {
		level = .Error
	} else if .WARNING in messageSeverity {
		level = .Warning
	} else if .INFO in messageSeverity {
		level = .Info
	} else {
		level = .Debug
	}

	log.log(level, pCallbackData.pMessage)
	return false
}

@(private = "file")
vk_pick_device :: proc() {
	device_count: u32
	vk_try(vk.EnumeratePhysicalDevices(g_instance, &device_count, nil))
	if device_count == 0 {
		log.panic("No GPU found!")
	}

	devices := make([]vk.PhysicalDevice, device_count, context.temp_allocator)
	vk_try(vk.EnumeratePhysicalDevices(g_instance, &device_count, raw_data(devices)))
	// Pick first
	g_physical_device = devices[0]
	props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(g_physical_device, &props)
	g_deviceName = bytes_to_string(&props.deviceName)
	vk.GetPhysicalDeviceMemoryProperties(g_physical_device, &g_mem_properties)
	log.infof("Selected device: %s", g_deviceName)
}

@(private = "file")
vk_create_logical_device :: proc() {
	if !find_queue_family_indexes() {
		log.panic("Cannot find device queues: graphics & present")
	}
	graphics_idx := g_queue_family_indexes.graphics
	device_create_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		pNext                   = &vk.PhysicalDeviceFeatures2 {
			sType = .PHYSICAL_DEVICE_FEATURES_2,
			features = {
				shaderInt64 = true
			},
			pNext = &vk.PhysicalDeviceVulkan13Features {
				sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
				pNext = &vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT {
					sType = .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT,
					extendedDynamicState = true,
				},
				synchronization2 = true,
				dynamicRendering = true,
				
			},
		},
		pQueueCreateInfos       = &vk.DeviceQueueCreateInfo {
			sType = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = graphics_idx,
			queueCount = 1,
			pQueuePriorities = raw_data([]f32{1}),
		},
		queueCreateInfoCount    = 1,
		ppEnabledExtensionNames = raw_data(DEVICE_EXTENSIONS),
		enabledExtensionCount   = u32(len(DEVICE_EXTENSIONS)),
	}
	vk_try(vk.CreateDevice(g_physical_device, &device_create_info, nil, &g_device))
	vk.GetDeviceQueue(g_device, graphics_idx, 0, &g_graphics_queue)
	vk.GetDeviceQueue(g_device, g_queue_family_indexes.present, 0, &g_present_queue)
}

@(private = "file")
find_queue_family_indexes :: proc() -> bool {
	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(g_physical_device, &count, nil)

	families := make([]vk.QueueFamilyProperties, count, context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(g_physical_device, &count, raw_data(families))

	graphics_idx := -1
	present_idx := -1
	for family, i in families {
		support_graphics_and_compute := .GRAPHICS in family.queueFlags && .COMPUTE in family.queueFlags
		support_present: b32
		vk_try(
			vk.GetPhysicalDeviceSurfaceSupportKHR(
				g_physical_device,
				u32(i),
				g_surface,
				&support_present,
			),
		)
		if support_graphics_and_compute {
			graphics_idx = i
		}
		if support_present {
			present_idx = i
		}
		if support_present && support_present {
			break
		}
	}
	if graphics_idx != -1 && present_idx != -1 {
		g_queue_family_indexes.graphics = u32(graphics_idx)
		g_queue_family_indexes.present = u32(present_idx)
		return true
	}
	return false
}

@(private = "file")
vk_create_swapchain :: proc() {
	{
		formats_count: u32
		vk_try(
			vk.GetPhysicalDeviceSurfaceFormatsKHR(
				g_physical_device,
				g_surface,
				&formats_count,
				nil,
			),
		)
		formats := make([]vk.SurfaceFormatKHR, formats_count, context.temp_allocator)
		vk_try(
			vk.GetPhysicalDeviceSurfaceFormatsKHR(
				g_physical_device,
				g_surface,
				&formats_count,
				raw_data(formats),
			),
		)
		present_mode_count: u32
		vk_try(
			vk.GetPhysicalDeviceSurfacePresentModesKHR(
				g_physical_device,
				g_surface,
				&present_mode_count,
				nil,
			),
		)
		present_modes := make([]vk.PresentModeKHR, present_mode_count, context.temp_allocator)
		vk_try(
			vk.GetPhysicalDeviceSurfacePresentModesKHR(
				g_physical_device,
				g_surface,
				&present_mode_count,
				raw_data(present_modes),
			),
		)
		capabilities: vk.SurfaceCapabilitiesKHR
		vk_try(
			vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(
				g_physical_device,
				g_surface,
				&capabilities,
			),
		)

		surface_format := choose_swapchain_surface_format(formats)
		present_mode := choose_swapchain_present_mode(present_modes)
		extent := choose_swapchain_extent(capabilities)
		g_swapchain_format = surface_format
		g_swapchain_extent = extent

		image_count := capabilities.minImageCount + 1
		if capabilities.maxImageCount > 0 {
			image_count = min(image_count, capabilities.maxImageCount)
		}

		create_info := vk.SwapchainCreateInfoKHR {
			sType            = .SWAPCHAIN_CREATE_INFO_KHR,
			surface          = g_surface,
			minImageCount    = image_count,
			imageFormat      = surface_format.format,
			imageColorSpace  = surface_format.colorSpace,
			presentMode      = present_mode,
			imageExtent      = extent,
			imageArrayLayers = 1,
			imageUsage       = {.COLOR_ATTACHMENT},
			preTransform     = capabilities.currentTransform,
			compositeAlpha   = {.OPAQUE},
			clipped          = true,
		}
		if g_queue_family_indexes.graphics != g_queue_family_indexes.present {
			create_info.imageSharingMode = .CONCURRENT
			create_info.queueFamilyIndexCount = 2
			create_info.pQueueFamilyIndices = raw_data(
				[]u32{g_queue_family_indexes.graphics, g_queue_family_indexes.present},
			)
		}
		vk_try(vk.CreateSwapchainKHR(g_device, &create_info, nil, &g_swapchain))
	}

	{
		image_count: u32
		vk_try(vk.GetSwapchainImagesKHR(g_device, g_swapchain, &image_count, nil))
		g_swapchain_image_count = image_count
		g_swapchain_images = make([]vk.Image, image_count)
		vk_try(
			vk.GetSwapchainImagesKHR(
				g_device,
				g_swapchain,
				&image_count,
				raw_data(g_swapchain_images),
			),
		)

		g_swapchain_image_views = make([]vk.ImageView, image_count)
		for image, i in g_swapchain_images {
			create_info := vk.ImageViewCreateInfo {
				sType = .IMAGE_VIEW_CREATE_INFO,
				image = image,
				viewType = .D2,
				format = g_swapchain_format.format,
				subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
			}
			vk_try(vk.CreateImageView(g_device, &create_info, nil, &g_swapchain_image_views[i]))
		}
	}

}

@(private = "file")
vk_destroy_swapchain :: proc() {
	for image_view in g_swapchain_image_views {
		vk.DestroyImageView(g_device, image_view, nil)
	}
	delete(g_swapchain_image_views)
	delete(g_swapchain_images)
	vk.DestroySwapchainKHR(g_device, g_swapchain, nil)
}

recreate_swapchain :: proc() {
	w, h := glfw.GetFramebufferSize(g_window)
	if w == 0 || h == 0 {
		return
	}
	vk.DeviceWaitIdle(g_device)
	vk_destroy_swapchain()
	vk_create_swapchain()
}

@(private = "file")
choose_swapchain_surface_format :: proc(formats: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
	for format in formats {
		if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
			return format
		}
	}
	return formats[0]
}

@(private = "file")
choose_swapchain_present_mode :: proc(modes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
	// for mode in modes {
	// 	if mode == .MAILBOX {
	// 		return .MAILBOX
	// 	}
	// }
	return .FIFO
}

@(private = "file")
choose_swapchain_extent :: proc(capabilities: vk.SurfaceCapabilitiesKHR) -> vk.Extent2D {
	if capabilities.currentExtent.width != max(u32) {
		return capabilities.currentExtent
	}

	width, height := glfw.GetFramebufferSize(g_window)
	return (vk.Extent2D {
				width = clamp(
					u32(width),
					capabilities.minImageExtent.width,
					capabilities.maxImageExtent.width,
				),
				height = clamp(
					u32(height),
					capabilities.minImageExtent.height,
					capabilities.maxImageExtent.height,
				),
			})
}
