let currentTickets = [];
let currentSelected = 1;

document.addEventListener('DOMContentLoaded', function () {
    const ui = document.getElementById('dispatch-ui');
    ui.setAttribute("tabindex", "0");
    ui.focus();
});

window.addEventListener('message', function(event) {
    const data = event.data;
    if (data.action === "show") {
        const ui = document.getElementById('dispatch-ui');
        ui.style.display = 'block';
        ui.setAttribute("tabindex", "0");
        ui.focus();
        currentTickets = data.tickets;
        currentSelected = data.selected;
        lastUpdate = Date.now();
        parkedSinceStart = {};
        for (let i = 0; i < currentTickets.length; i++) {
            let t = currentTickets[i];
            parkedSinceStart[t.plate] = t.parkedSince;
        }
        updateTicketList();
    } else if (data.action === "hide") {
        document.getElementById('dispatch-ui').style.display = 'none';
        currentTickets = [];
        parkedSinceStart = {};
    }
});

function updateTicketList() {
    const list = document.getElementById('ticket-list');
    if (currentTickets.length === 0) {
        currentSelected = 1;
        list.innerHTML = `
            <div class="ticket-info">
                <strong>Plate:</strong> -<br>
                <strong>Parked:</strong> -<br>
                <strong>Task:</strong> 0/0
            </div>
        `;
        return;
    }
    currentSelected = Math.max(1, Math.min(currentSelected, currentTickets.length));
    const t = currentTickets[currentSelected - 1];
    if (t) {
        fetch(`https://${GetParentResourceName()}/getParkovaneTime`, {
            method: 'POST',
            body: JSON.stringify({ selected: currentSelected })
        })
        .then(resp => resp.json())
        .then(formatted => {
            list.innerHTML = `
                <div class="ticket-info">
                    <strong>Plate:</strong> ${t.plate}<br>
                    <strong>Parked:</strong> ${formatted}<br>
                    <strong>Task:</strong> ${currentSelected}/${currentTickets.length}
                </div>
            `;
        });
    }
}

setInterval(function() {
    const ui = document.getElementById('dispatch-ui');
    if (ui && window.getComputedStyle(ui).display !== 'none') {
        updateTicketList();
    }
}, 1000);

document.getElementById('arrow-left').onclick = function() {
    if (currentTickets.length > 0) {
        currentSelected = Math.max(1, currentSelected - 1);
        updateTicketList();
        fetch(`https://${GetParentResourceName()}/dispatchNavigate`, {
            method: 'POST',
            body: JSON.stringify({ dir: "setSelected", selected: currentSelected })
        });
    }
};

document.getElementById('arrow-right').onclick = function() {
    if (currentTickets.length > 0) {
        currentSelected = Math.min(currentTickets.length, currentSelected + 1);
        updateTicketList();
        fetch(`https://${GetParentResourceName()}/dispatchNavigate`, {
            method: 'POST',
            body: JSON.stringify({ dir: "setSelected", selected: currentSelected })
        });
    }
};

document.getElementById('waypoint-btn').onclick = function() {
    if (currentTickets.length > 0) {
        fetch(`https://${GetParentResourceName()}/dispatchWaypoint`, {
            method: 'POST',
            body: JSON.stringify({ selected: currentSelected })
        });
    }
};

function isChatOpen() {
    return document.activeElement.tagName === 'INPUT' || document.activeElement.tagName === 'TEXTAREA';
}

window.addEventListener('keydown', function(e) {
    const ui = document.getElementById('dispatch-ui');
    if (ui && window.getComputedStyle(ui).display !== 'none' && !isChatOpen()) {
        if (e.code === 'ArrowLeft') {
            if (currentTickets.length > 0) {
                currentSelected = Math.max(1, currentSelected - 1);
                updateTicketList();
                fetch(`https://${GetParentResourceName()}/dispatchNavigate`, {
                    method: 'POST',
                    body: JSON.stringify({ dir: "setSelected", selected: currentSelected })
                });
            }
        } else if (e.code === 'ArrowRight') {
            if (currentTickets.length > 0) {
                currentSelected = Math.min(currentTickets.length, currentSelected + 1);
                updateTicketList();
                fetch(`https://${GetParentResourceName()}/dispatchNavigate`, {
                    method: 'POST',
                    body: JSON.stringify({ dir: "setSelected", selected: currentSelected })
                });
            }
        } else if (e.code === 'KeyG') {
            if (currentTickets.length > 0) {
                document.getElementById('waypoint-btn').click();
            }
        }
    }
});
