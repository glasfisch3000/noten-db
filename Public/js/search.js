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
	
	fetch("/search?search=" + encodeURIComponent(searchInput.value), {
		method: "get",
		signal: controller.signal,
	})
	.then(applySearch)
	.catch(cancelSearch)
})

async function applySearch(response) {
	searchResults.textContent = ""
	
	if (response.ok) {
		let sheets = await response.json()
		for (let sheet of sheets) {
			let parent = document.createElement("div")
			parent.classList.add("search-item")
			searchResults.appendChild(parent)
			
			let preview = document.createElement("div")
			preview.classList.add("item-preview")
			parent.appendChild(preview)
			let img = document.createElement("img")
			img.src = `/${sheet.id}/file`
			preview.appendChild(img)
			
			let info = document.createElement("div")
			info.classList.add("item-info")
			parent.appendChild(info)
			
			let title = document.createElement("div")
			title.classList.add("item-title")
			title.textContent = sheet.title
			info.appendChild(title)
			
			if (sheet.composer) {
				let composer = document.createElement("div")
				composer.classList.add("item-composer")
				composer.textContent = sheet.composer
				info.appendChild(composer)
			}
			
			if (sheet.arranger) {
				let arranger = document.createElement("div")
				arranger.classList.add("item-arranger")
				arranger.textContent = sheet.arranger
				info.appendChild(arranger)
			}
		}
	} else {
		let error = document.createElement("div")
		error.classList.add("error")
		error.textContent = "Suche fehlgeschlagen"
		searchResults.prepend(error)
	}
}

function cancelSearch(error) {
	searchResults.textContent = ""
}
