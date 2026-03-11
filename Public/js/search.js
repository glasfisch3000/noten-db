let searchButton = document.getElementById("search-button-input")
let controller = new AbortController()
searchButton.addEventListener("change", (event) => {
	if (searchButton.checked) {
		searchInput.focus()
	} else {
		controller.abort()
	}
})

let searchInput = document.getElementById("search-input")
let searchResults = document.getElementById("search-results")
searchInput.addEventListener("input", (event) => {
	controller.abort()
	if (!searchInput.value) {
		return
	}
	
	controller = new AbortController()
	
	fetch("/search/api?search=" + encodeURIComponent(searchInput.value), {
		method: "get",
		signal: controller.signal,
	})
	.then(applySearch)
	.catch(cancelSearch)
})

function applySearch(response) {
	console.log(response)
	if (response.ok) {
		// TODO
	} else {
		searchResults.textContent = ""
		
		let error = document.createElement("div")
		error.classList.add("error")
		error.textContent = "Suche fehlgeschlagen"
		searchResults.prepend(error)
	}
}

function cancelSearch(error) {
	searchResults.textContent = ""
}
