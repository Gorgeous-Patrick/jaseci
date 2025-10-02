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


void run_on_node(uint64_t ability_type, void * node_buffer, void * walker_buffer, uint64_t edge_num);

#define MAX_CONTAINER_BUFFER_SIZE 128
uint64_t container_buffer[MAX_CONTAINER_BUFFER_SIZE];
uint64_t container_buffer_size = 0;

void run_thread(uint64_t walker_container_ptr, uint64_t trace_length) {
    ContainerObject container_obj;
    for (uint64_t i = 0; i < trace_length; i++) {
        get(&container_obj, walker_container_ptr + i * sizeof(ContainerObject), sizeof(ContainerObject));
        #ifdef DEBUG
        printf("Container Object %lu: Ability type: %lu, Node id: %lu, Walker id: %lu\n", i, container_obj.ability_type, container_obj.node_id, container_obj.walker_id);
        #endif
        // Load node
        get(node_buffer, container_obj.node_ptr, container_obj.node_size);
        // Load walker
        get(walker_buffer, container_obj.walker_ptr, container_obj.walker_size);
        // Run on node
        run_on_node(container_obj.ability_type, node_buffer, walker_buffer, container_obj.edge_num);
        // Save walker
        save(walker_buffer, container_obj.walker_ptr, container_obj.walker_size);
        // Save node
        save(node_buffer, container_obj.node_ptr, container_obj.node_size);
    }
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

int main() {
    uint64_t walker_id = me();
    if (walker_id == 0) {
        mem_init();
    }
    // Barrier
    barrier_wait(&my_barrier);
    Metadata metadata;
    get(&metadata, DPU_MRAM_HEAP_POINTER, sizeof(Metadata));
    #ifdef DEBUG
    printf("DPU Tasklet %u: Walker ptr: %lu, Walker size: %lu, Node size: %lu, Edge num: %lu\n", walker_id, metadata.walker_ptr, metadata.walker_size, metadata.node_size, metadata.edge_num);
    #endif
    if (walker_id >= metadata.walker_num) {
        return 0;
    }

    uint64_t walker_container_ptr = metadata.walker_container_ptrs[walker_id];
    uint64_t trace_length = metadata.trace_lengths[walker_id];
    #ifdef DEBUG
    printf("DPU Tasklet %u: Walker container ptr: %lu, Trace length: %lu\n", walker_id, walker_container_ptr, trace_length);
    #endif

}