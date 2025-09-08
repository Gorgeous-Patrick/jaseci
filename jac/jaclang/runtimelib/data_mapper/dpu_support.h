#include <stdint.h>
#include <stdio.h>
#include <defs.h>
#include <mram.h>
#include <alloc.h>
#include <perfcounter.h>
#include <barrier.h>

#include "../support/common.h"
// #define DEBUG

__host dpu_arguments_t DPU_INPUT_ARGUMENTS;

void get_node(node_t *node, uint32_t node_id) {
    // Read the node from MRAM
    uint32_t addr = DPU_MRAM_HEAP_POINTER + node_id * aligned_malloc_size(sizeof(node_t));
    mram_read((__mram_ptr void*)(addr), node, aligned_malloc_size(sizeof(node_t)));
}

void save_node(node_t *node, uint32_t node_id) {
    // Write the node back to MRAM
    uint32_t addr = DPU_MRAM_HEAP_POINTER + node_id * aligned_malloc_size(sizeof(node_t));
    mram_write(node, (__mram_ptr void*)(addr), aligned_malloc_size(sizeof(node_t)));
}

void get_walker(walker_t *walker) {
    // Read the walker from MRAM
    uint32_t addr = DPU_MRAM_HEAP_POINTER + DPU_INPUT_ARGUMENTS.num_nodes_assigned * aligned_malloc_size(sizeof(node_t));
    mram_read((__mram_ptr void*)(addr), walker, aligned_malloc_size(sizeof(walker_t)));
}

void save_walker(walker_t *walker) {
    // Write the walker back to MRAM
    uint32_t addr = DPU_MRAM_HEAP_POINTER + DPU_INPUT_ARGUMENTS.num_nodes_assigned * aligned_malloc_size(sizeof(node_t));
    mram_write(walker, (__mram_ptr void*)(addr), aligned_malloc_size(sizeof(walker_t)));
}

node_t *node_buffer;
walker_t *walker_buffer;
#define MAX_CONTAINER_BUFFER_SIZE 128
uint64_t container_buffer[MAX_CONTAINER_BUFFER_SIZE];
uint64_t container_buffer_size = 0;
void mem_init() {
    // Initialize the memory for the container value buffer, only one uint32_t.
    node_buffer = (node_t *) mem_alloc(aligned_malloc_size(sizeof(node_t)));
    walker_buffer = (walker_t *) mem_alloc(aligned_malloc_size(sizeof(walker_t)));
}

void push_new_element_to_container(uint32_t id) {
    #ifdef DEBUG
    printf("Pushing new element to container: %u\n", id);
    #endif
    if (container_buffer_size < MAX_CONTAINER_BUFFER_SIZE) {
        container_buffer[container_buffer_size++] = id;
    } else {
        #ifdef DEBUG
        printf("Container buffer overflow, cannot push new element: %u\n", id);
        #endif
    }
}

void print_container() {
    printf("Container contents: ");
    for (uint32_t i = 0; i < container_buffer_size; i++) {
        printf("%lu ", container_buffer[i]);
    }
    printf("\n");
}