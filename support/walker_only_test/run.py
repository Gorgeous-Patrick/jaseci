import os
import json
import requests
import time
import csv

jaseci_path = "/jaseci/jaseci_kit/jaseci_kit/modules"

# def initCommand():
#     return "jsctl -f session login http://clarity31.eecs.umich.edu:8080 --username jaclang0@jaseci.org --password ilovejaclang0"

# def getSntCommand(codePath: str):
#     abspath = os.path.abspath(codePath)
#     return f"jsctl -f session sentinel register {abspath}"

# def getRunCommand(walkerName: str):
#     return f"jsctl -f session walker run {walkerName}"


def localActionPath(kit_module: str):
    return os.path.join(jaseci_path, kit_module)


# def getActionLoadCommand(module_path: str):
#     return f"jsctl actions load local {module_path}"
# os.system(initCommand())
# os.system(getActionLoadCommand(localActionPath("entity_extraction/entity_extraction.py")))
# os.system(getRunCommand("bi_enc/cos_sim_score.jac"))

HOST = "http://clarity3.eecs.umich.edu:30001"
auth_header = {}


def login():
    userName = "jaclang0@jaseci.org"
    password = "ilovejaclang0"
    response = requests.post(
        HOST + "/user/token/", json={"email": userName, "password": password}
    )
    token = response.json()["token"]
    global auth_header
    auth_header["authorization"] = f"Token {token}"
    print(auth_header)
    return auth_header


def load_module_actions(abs_path: str):
    response = requests.post(
        HOST + "/js_admin/actions_load_module",
        headers=auth_header,
        json={"mod": abs_path},
    )
    print(f"Load Actions (module): {response.text}")


def load_actions(abs_path: str):
    response = requests.post(
        HOST + "/js_admin/actions_load_local",
        headers=auth_header,
        json={"file": abs_path},
    )
    print(f"Load Actions (local): {response.text}")


def getSentinel(codePath: str):
    file = open(codePath, "r")
    code = file.read()
    file.close()
    print(code)
    req = {
        "name": "jac_prog_testers2",
        "code": code,
    }
    response = requests.post(
        HOST + "/js/sentinel_register",
        headers=auth_header,
        json=req,
    )
    print(f"Sentinel: f{response.text}")
    snt = response.json()[0]["jid"]
    response = requests.post(
        HOST + "/js/graph_create", headers=auth_header, json={"set_active": True}
    )
    print(f"Create Graph: f{response.text}")
    return snt


def walkerRun(SNT, req):
    response = requests.post(HOST + "/js/walker_run", headers=auth_header, json=req)
    walkerName = req["name"]
    print(f"Walker Run ({walkerName}): f{response.text}")


login()
snt = getSentinel("zsb/zsb.jac")
json = {
    "name": "add_bot",
    "nd": "active:graph",
    "ctx": {
        "name": "locustBot",
        "description": "this is a test bot for Locust testing",
    },
    "snt": "active:sentinel",
}

walkerRun(snt, json)
