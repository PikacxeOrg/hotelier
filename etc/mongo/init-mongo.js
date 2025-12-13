db = db.getSiblingDB("hotelier_notification");
db.createUser({
    user: "hotelier",
    pwd: "hotelier",
    roles: [{ role: "readWrite", db: "hotelier_notification" }],
});

db = db.getSiblingDB("hotelier_search");
db.createUser({
    user: "hotelier",
    pwd: "hotelier",
    roles: [{ role: "readWrite", db: "hotelier_search" }],
});
