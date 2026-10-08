export namespace windows {
	
	export class CoreServiceStatus {
	    installed: boolean;
	    running: boolean;
	    state: string;
	    stateText: string;
	    executablePath: string;
	    isElevated: boolean;
	    canInstall: boolean;
	    message: string;
	
	    static createFrom(source: any = {}) {
	        return new CoreServiceStatus(source);
	    }
	
	    constructor(source: any = {}) {
	        if ('string' === typeof source) source = JSON.parse(source);
	        this.installed = source["installed"];
	        this.running = source["running"];
	        this.state = source["state"];
	        this.stateText = source["stateText"];
	        this.executablePath = source["executablePath"];
	        this.isElevated = source["isElevated"];
	        this.canInstall = source["canInstall"];
	        this.message = source["message"];
	    }
	}

}

