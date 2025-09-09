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

void get(void * buf, uint32_t start, uint32_t size) {
    // Read the node from MRAM
    uint32_t addr = DPU_MRAM_HEAP_POINTER + start;
    mram_read((__mram_ptr void*)(addr), buf, size);
}

void save(void * buf, uint32_t start, uint32_t size) {
    // Write the walker back to MRAM
    uint32_t addr = DPU_MRAM_HEAP_POINTER + start;
    mram_write(walker, (__mram_ptr void*)(addr), size);

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

struct BranchNode {
uint64_t mid;
};

struct DataNode {
uint64_t value; uint64_t index;
};



struct bs {
uint64_t value;
};


void printnode_bs_DataNode (DataNode *node, uint32_t node_id, bs* walker) {
1;
}

void rundown_bs_BranchNode (BranchNode *node, uint32_t node_id, bs* walker) {
1;
}


void *node_buffer;
void *walker_buffer;
void mem_init() {
    node_buffer = mem_alloc(16);
    walker_buffer = mem_alloc(8);
}

int main_kernel1() {
    // Barrier
    // barrier_wait(&my_barrier);


    // Get number of nodes and walkers assigned
    uint32_t num_nodes_assigned = DPU_INPUT_ARGUMENTS.num_nodes_assigned;

    #ifdef DEBUG
    printf("num_nodes_assigned = %u\n", num_nodes_assigned);
    #endif


    int cnt = 0;
    get_walker(walker_buffer);
    
    if (task_id == 0) {
    
    get_node(node_buffer, 0, 8); 
    rundown_bs_BranchNode(node_buffer, 0, walker_buffer);
    save_node(node_buffer, 0, 8); 
    
    get_node(node_buffer, 48, 8); 
    rundown_bs_BranchNode(node_buffer, 2, walker_buffer);
    save_node(node_buffer, 48, 8); 
    
    get_node(node_buffer, 56, 16); 
    printnode_bs_DataNode(node_buffer, 5, walker_buffer);
    save_node(node_buffer, 56, 16); 
    
    }
    

    save_walker(walker_buffer);
    #ifdef DEBUG
    printf("Ending.\n");
    print_container();
    #endif
    // mram_write(&sum, (__mram_ptr void*)(DPU_MRAM_HEAP_POINTER), aligned_malloc_size(sizeof(uint32_t)));
    return 0;
}

int main() { 
    // Kernel
    // return kernels[DPU_INPUT_ARGUMENTS.kernel](); 
    // Initialize memory
    unsigned int tasklet_id = me();

    #ifdef DEBUG
    printf("tasklet_id = %u\n", tasklet_id);
    #endif
    if (tasklet_id == 0){ // Initialize once the cycle counter
        mem_reset(); // Reset the heap
    }
    mem_init();
    return 0;
    return main_kernel1(); // Directly call the main_kernel1 function
}