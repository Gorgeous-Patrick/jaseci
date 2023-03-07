DB_MANIFEST = {
    "Service": [
        {
            "kind": "Service",
            "apiVersion": "v1",
            "metadata": {"name": "jaseci-db"},
            "spec": {
                "selector": {"pod": "jaseci-db"},
                "ports": [{"protocol": "TCP", "port": 5432, "targetPort": 5432}],
            },
        }
    ],
    "Deployment": [
        {
            "apiVersion": "apps/v1",
            "kind": "Deployment",
            "metadata": {"name": "jaseci-db"},
            "spec": {
                "replicas": 1,
                "selector": {"matchLabels": {"pod": "jaseci-db"}},
                "template": {
                    "metadata": {"labels": {"pod": "jaseci-db"}},
                    "spec": {
                        "containers": [
                            {
                                "name": "jaseci-db",
                                "image": "postgres:alpine",
                                "imagePullPolicy": "IfNotPresent",
                                "env": [
                                    {
                                        "name": "POSTGRES_USER",
                                        "valueFrom": {
                                            "secretKeyRef": {
                                                "name": "jaseci-db-credentials",
                                                "key": "user",
                                            }
                                        },
                                    },
                                    {
                                        "name": "POSTGRES_PASSWORD",
                                        "valueFrom": {
                                            "secretKeyRef": {
                                                "name": "jaseci-db-credentials",
                                                "key": "password",
                                            }
                                        },
                                    },
                                ],
                                "ports": [{"containerPort": 5432}],
                                "volumeMounts": [
                                    {
                                        "name": "jaseci-db-volume",
                                        "mountPath": "/var/lib/postgresql/data",
                                        "subPath": "jaseci",
                                    }
                                ],
                            }
                        ],
                        "volumes": [
                            {
                                "name": "jaseci-db-volume",
                                "persistentVolumeClaim": {"claimName": "jaseci-db-pvc"},
                            }
                        ],
                    },
                },
            },
        }
    ],
    "Secret": [
        {
            "apiVersion": "v1",
            "kind": "Secret",
            "metadata": {"name": "jaseci-db-credentials"},
            "type": "Opaque",
            "data": {"user": "cG9zdGdyZXM=", "password": "bGlmZWxvZ2lmeWphc2VjaQ=="},
        }
    ],
    "PersistantVolumeClaim": [
        {
            "kind": "PersistentVolumeClaim",
            "apiVersion": "v1",
            "metadata": {"name": "jaseci-db-pvc"},
            "spec": {
                "accessModes": ["ReadWriteOnce"],
                "resources": {"requests": {"storage": "10Gi"}},
            },
        }
    ],
}
