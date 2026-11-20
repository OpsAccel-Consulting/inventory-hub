// Confirm destructive actions and auto-dismiss flash messages.
document.addEventListener("submit", (event) => {
  const message = event.target.dataset.confirm;
  if (message && !window.confirm(message)) {
    event.preventDefault();
  }
});

setTimeout(() => {
  document.querySelectorAll(".flash").forEach((el) => {
    el.style.transition = "opacity .4s";
    el.style.opacity = "0";
    setTimeout(() => el.remove(), 400);
  });
}, 4000);
