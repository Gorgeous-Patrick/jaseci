#include <stdint.h>
#include <stdio.h>
#include <defs.h>
#include <mram.h>
#include <alloc.h>
#include <perfcounter.h>
#include <barrier.h>

// #define DEBUG

typedef struct __Mem_Range{
    uint32_t ptr;
    uint32_t size;
    uint64_t ability_type;
    uint64_t outgoing_edges;
} Mem_Range;

void get(void * buf, uint32_t start, uint32_t size) {
    // Read the node from MRAM
    uint32_t addr = DPU_MRAM_HEAP_POINTER + start;
    mram_read((__mram_ptr void*)(addr), buf, size);
}

void save(void * buf, uint32_t start, uint32_t size) {
    // Write the walker back to MRAM
    uint32_t addr = DPU_MRAM_HEAP_POINTER + start;
    mram_write(buf, (__mram_ptr void*)(addr), size);
}


void run_on_node(uint64_t ability_type, void * node_buffer, void * walker_buffer);

#define MAX_CONTAINER_BUFFER_SIZE 128
uint64_t container_buffer[MAX_CONTAINER_BUFFER_SIZE];
uint64_t container_buffer_size = 0;

void run_thread(uint32_t node_num, Mem_Range * node_ranges, Mem_Range walker_range, uint32_t node_buffer_size, uint32_t walker_buffer_size) {
    void *node_buffer;
    void *walker_buffer;
    node_buffer = mem_alloc(node_buffer_size);
    walker_buffer = mem_alloc(walker_buffer_size);
    get(walker_buffer, walker_range.ptr, walker_range.size);
    for (uint32_t i = 0; i < node_num; i++) {
        Mem_Range nr = node_ranges[i];
        get(node_buffer, nr.ptr, nr.size);
        run_on_node(nr.ability_type, node_buffer, walker_buffer);
        save(node_buffer, nr.ptr, nr.size);
    }
    save(walker_buffer, walker_range.ptr, walker_range.size);
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
