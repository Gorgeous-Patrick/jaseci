# <span style="color: orange">Building AI Agents: Fantasy Trading Game

This tutorial shows how to build AI agents with persistent state that can conduct conversations, execute trades, and maintain context across interactions. You'll also learn to integrate AI functions for character generation and dialogue.

## <span style="color: orange">What You'll Build

A trading game with:
- AI-powered character generation functions
- AI agents that maintain conversation state
- Trading transaction system
- Persistent conversation history
- Context-aware decision making

## <span style="color: orange">Prerequisites

Before starting, install the required dependencies:

```bash
pip install mtllm
```

Set up your OpenAI API key:
```bash
export OPENAI_API_KEY="your-api-key-here"
```

## <span style="color: orange">Step 1: Define Data Structures

Start by defining objects that represent your game world:

```jac
obj InventoryItem {
    has name: str;
    has price: float;
}

obj Person {
    has name: str;
    has age: int;
    has hobby: str;
    has description: str;
    has money: float;
    has inventory: list[InventoryItem];
}

obj Chat {
    has person: str;
    has message: str;
}
```

These structures define:
- **InventoryItem**: Tradeable objects with name and price
- **Person**: Character data including stats, money, and items
- **Chat**: Message history for conversation context

## <span style="color: orange">Step 2: Configure the AI Model

Set up your LLM for AI operations:

```jac
import from mtllm.llms {OpenAI}

glob llm = OpenAI(model_name="gpt-4o");
```

## <span style="color: orange">Step 3: Create AI-Powered Character Generation

Build AI-integrated functions that generate game characters:

```jac
def make_player() -> Person by llm();

def make_random_npc() -> Person by llm();
```

These AI functions generate characters with appropriate attributes, starting money, and themed inventory items.

## <span style="color: orange">Step 4: Implement Game Logic

Create functions for core game mechanics:

```jac
def make_transaction(buyer_name: str, seller_name: str, item_name: str, price: int| None = None) -> bool {
    buyer = person_record[buyer_name];
    seller = person_record[seller_name];

    # Find item in seller's inventory
    item_to_buy = None;
    item_index = -1;
    for i in range(len(seller.inventory)) {
        if seller.inventory[i].name.lower() == item_name.lower() {
            item_to_buy = seller.inventory[i];
            item_index = i;
            break;
        }
    }

    price = price or item_to_buy.price;

    # Validate transaction
    if not item_to_buy or buyer.money < price {
        return False;
    }

    # Execute transfer
    buyer.money -= price;
    seller.money += price;
    buyer.inventory.append(item_to_buy);
    seller.inventory.pop(item_index);
    return True;
}
```

This function:
1. Locates the item in the seller's inventory
2. Validates the buyer has sufficient funds
3. Transfers money and items between characters

## <span style="color: orange">Step 5: Build Conversational AI Agent

Create an AI agent that maintains state and can take actions:

```jac
def chat_with_player(player: Person, npc: Person, chat_history: list[Chat]) -> Chat
    by llm(method="ReAct", tools=[make_transaction]);
```

This is an AI agent because it:
- **Maintains State**: Uses `chat_history` to remember previous interactions
- **Reasons**: Thinks about the conversation context using ReAct method
- **Acts**: Can use tools like `make_transaction` when appropriate
- **Persists Context**: Builds understanding across multiple conversation turns

The agent capabilities:
- Remember previous conversations through persistent `chat_history`
- Execute trades when agreements are reached
- Negotiate prices within reasonable bounds
- Stay in character while being functional

## <span style="color: orange">Step 6: Implement the Game Loop

Connect all components in the main execution:

```jac
with entry {
    # Generate characters using AI functions
    player = make_player();
    npc = make_random_npc();

    # Register characters for transactions
    person_record[player.name] = player;
    person_record[npc.name] = npc;

    history = [];

    while True {
        # AI agent generates response with state
        chat = chat_with_player(player, npc, history);
        history.append(chat);

        # Display game state
        for p in [player, npc] {
            print(p.name, ":  $", p.money);
            for i in p.inventory {
                print("  ", i.name, ":  $", i.price);
            }
        }

        # Show NPC response and get player input
        print("\n[[npc]] >> ", chat.message);
        inp = input("\n[[Player input]] >> ");
        history.append(Chat(person=player.name, message=inp));
    }
}
```

The game loop:
1. Uses AI functions to generate characters (stateless)
2. Registers characters for transaction system
3. Uses the AI agent for NPC responses (stateful - maintains conversation history)
4. Accumulates conversation history for persistent context
5. Displays current game state after each interaction

## <span style="color: orange">AI Functions vs AI Agents

### <span style="color: orange">AI Functions (Stateless)

AI-integrated functions that don't maintain persistent state:
- `make_player()` and `make_random_npc()` - Generate characters but don't remember
- These are AI-powered utilities, not agents

### <span style="color: orange">AI Agents (Stateful)

AI systems that maintain persistent state across interactions:
- `chat_with_player()` with `chat_history` parameter - Remembers conversation context
- Builds understanding over multiple turns
- Can reference previous interactions

## <span style="color: orange">Key Concepts

### <span style="color: orange">Tool Integration

The AI agent can access application functions through tools:
- The `chat_with_player` AI agent can call `make_transaction`
- The AI extracts parameters from natural language
- Tool results are incorporated into responses

### <span style="color: orange">State Management

The AI agent maintains state through:
- Structured data objects (`Person`, `InventoryItem`)
- Conversation history (`Chat` objects)
- Global registries (`person_record`)

## <span style="color: orange">Running the Tutorial

1. Install dependencies: `pip install mtllm`
2. Configure OpenAI API key
3. Run: `jac run fantasy_trading_game.jac`
4. Interact with the AI agent through natural language

➡️ [Complete Source Code](https://github.com/jaseci-labs/jaseci/blob/main/jac-mtllm/examples/fantasy_trading_game.jac)

## <span style="color: orange">Example Interaction

```
[[Npc]] >> Greetings, traveler! I am Thornwick the Wise, an ancient dwarf
with a passion for collecting rare gemstones. I've been mining these
mountains for over 200 years. I notice you carry yourself like an
adventurer - perhaps we could do some trading?

[[Player]] >> Hello! What do you have for sale?

[[Npc]] >> Ah, a direct sort - I like that! I have several treasures from
my decades of mining. I have a pristine Moonstone Amulet that glows with
inner light for 75 gold pieces, and a rare Dwarven Pickaxe forged by my
grandfather for 120 gold. What catches your interest, friend?
```

## <span style="color: orange">Summary

This tutorial demonstrates building AI agents with persistent state alongside AI-powered functions. The `chat_with_player` agent maintains conversation history and can execute trades through tool integration, while character generation functions provide stateless AI capabilities. The structured datatypes serve as a vocabulary for communicating game concepts to the AI, enabling natural language interactions that result in functional game mechanics.