"""Client-side runtime for Jac JSX and walker interactions."""

# JSX factory function
cl def __jacJsx(tag: any, props: dict = {}, children: list = []) -> dict {
    return {"tag": tag, "props": props, "children": children};
}

# DOM rendering function
cl def renderJsxTree(node: any, container: any) -> None {
    container.replaceChildren(__buildDom(node));
}

# Internal: Build DOM from JSX tree
cl def __buildDom(node: any) -> any {
    if node == None {
        return __createTextNode("");
    }

    if not __isObject(node) {
        return __createTextNode(__toString(node));
    }

    # Handle component functions
    tag = node.get("tag");
    if __isFunction(tag) {
        props = node.get("props", {});
        return __buildDom(tag(props));
    }

    # Create element
    element = __createElement(tag if tag else "div");

    # Apply properties
    props = node.get("props", {});
    for key in __objectKeys(props) {
        value = props.get(key);
        __applyProp(element, key, value);
    }

    # Render children
    children = node.get("children", []);
    for child in children {
        childDom = __buildDom(child);
        if childDom {
            element.appendChild(childDom);
        }
    }

    return element;
}

# Internal: Apply property to DOM element
cl def __applyProp(element: any, key: str, value: any) -> None {
    if key.startswith("on") {
        # Event handler: onclick -> click
        event = key[2:].lower();
        element.addEventListener(event, value);
    } elif key == "className" or key == "class" {
        element.className = value;
    } elif key == "style" and __isObject(value) {
        # Style object
        for styleKey in __objectKeys(value) {
            element.style[styleKey] = value.get(styleKey);
        }
    } elif key != "children" {
        element.setAttribute(key, __toString(value));
    }
}

# Walker spawn function
cl async def __jacSpawn(walker: str, fields: dict = {}) -> any {
    token = __getLocalStorage("jac_token");

    response = await __fetch(
        f"/walker/{walker}",
        {
            "method": "POST",
            "headers": {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {token}" if token else ""
            },
            "body": __jsonStringify({"nd": "root", **fields})
        }
    );

    if not response.ok {
        error_text = await response.text();
        raise Exception(f"Walker {walker} failed: {error_text}");
    }

    return __jsonParse(await response.text());
}

# Authentication helpers
cl async def jacLogin(username: str, password: str) -> bool {
    response = await __fetch(
        "/user/login",
        {
            "method": "POST",
            "headers": {"Content-Type": "application/json"},
            "body": __jsonStringify({"username": username, "password": password})
        }
    );

    if response.ok {
        data = __jsonParse(await response.text());
        token = data.get("token");
        if token {
            __setLocalStorage("jac_token", token);
            return True;
        }
    }
    return False;
}

cl def jacLogout() -> None {
    __removeLocalStorage("jac_token");
}

cl def jacIsLoggedIn() -> bool {
    token = __getLocalStorage("jac_token");
    return token != None and token != "";
}

# Browser API shims
cl async def __fetch(url: str, options: dict = {}) -> any {
    fetch_opts = options if options else {};
    return await fetch(url, fetch_opts);
}

cl def __getLocalStorage(key: str) -> str {
    storage = globalThis.localStorage;
    return storage.getItem(key) if storage else "";
}

cl def __setLocalStorage(key: str, value: str) -> None {
    storage = globalThis.localStorage;
    if storage {
        storage.setItem(key, value);
    }
}

cl def __removeLocalStorage(key: str) -> None {
    storage = globalThis.localStorage;
    if storage {
        storage.removeItem(key);
    }
}

cl def __jsonStringify(obj: any) -> str {
    return JSON.stringify(obj);
}

cl def __jsonParse(text: str) -> any {
    return JSON.parse(text);
}

cl def __createElement(tag: str) -> any {
    return document.createElement(tag);
}

cl def __createTextNode(text: str) -> any {
    return document.createTextNode(text);
}

cl def __isObject(value: any) -> bool {
    if value == None {
        return False;
    }
    return Object.prototype.toString.call(value) == "[object Object]";
}

cl def __isFunction(value: any) -> bool {
    return Object.prototype.toString.call(value) == "[object Function]";
}

cl def __toString(value: any) -> str {
    return String(value);
}

cl def __objectKeys(obj: any) -> list {
    if obj == None {
        return [];
    }
    return Object.keys(obj);
}
