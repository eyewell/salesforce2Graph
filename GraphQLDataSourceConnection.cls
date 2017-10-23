global with sharing class GraphQLDataSourceConnection extends DataSource.Connection {

	private DataSource.ConnectionParams connectionInfo;
	private String url = '';
	//private String username = '';
	//private String password = '';  
 
	global GraphQLDataSourceConnection(){
	}

	global GraphQLDataSourceConnection(DataSource.ConnectionParams connectionParams) {
		connectionInfo = connectionParams;
		url = connectionInfo.endPoint;
		
		//this.connectionInfo = connectionParams;
		//this.url = this.connectionInfo.endPoint;
		
		// simplify
		//this.username = this.connectionInfo.username;
		//this.password = this.connectionInfo.password;
	}

	// To get meta data from the swagger service and create external objects
	override global List<DataSource.Table> sync(){
		
		List<DataSource.Table> tables = new List<DataSource.Table>();
        List<DataSource.Column> columns;
        columns = new List<DataSource.Column>();
        columns.add(DataSource.Column.text('Name', 255));
        columns.add(DataSource.Column.text('Born', 255));
        columns.add(DataSource.Column.text('ExternalId', 255));
        columns.add(DataSource.Column.url('DisplayUrl'));
        tables.add(DataSource.Table.get('Person', 'Name',columns));
        return tables;
		
		
	}


	// Used to query external system data
	//QUERY
	//
	override global DataSource.TableResult query(DataSource.QueryContext c){
		DataSource.Filter filter = c.tableSelection.filter;
		Integer offset = c.offset;
		Integer maxResults = c.maxResults;	

		string entity = c.tableSelection.tableSelected;
		//string call_url = url; 								//populated in constructor
		string display_url = url + '/api/' + entity +'s/';
		string payload = '{  "statements": [    { "statement": '; //initialize the REST URL wit opening statements, payload to be added later
		
		if(filter == null){
			
			//if no filter, the just retrieve all records
			if (entity == 'Person') 
				{
					payload = payload + '"MATCH (n:Person) RETURN n",';
				}
			
				//TODO: add paging and sorting
				//call_url = url + '/api/'+ entity + 's' + addPagingFilters(offset, maxResults, true) + addSortFilters(c.tableSelection.order, false);					
			
		}
		
		else if(filter != null){
			//if there are filters, then add them to the query
			
			String cName = filter.columnName;
			String Operator;
			
			//set the operators that the graph QL expects
			if (filter.type != null){
				if      (filter.type == DataSource.FilterType.GREATER_THAN)             Operator = '>';
				else if (filter.type == DataSource.FilterType.LESS_THAN)                Operator = '<';
				else if (filter.type == DataSource.FilterType.GREATER_THAN_OR_EQUAL_TO) Operator = '>=';
				else if (filter.type == DataSource.FilterType.LESS_THAN_OR_EQUAL_TO)    Operator = '<=';
				else if (filter.type == DataSource.FilterType.EQUALS)                   Operator = '=';
				else if (filter.type == DataSource.FilterType.NOT_EQUALS)               Operator = '<>'; 
			}
            
            
            //now handle the queries
			if (cName != null && cName.equals('ExternalId')){
				
				//This section used to query "All" records in the external object's tab
				payload = payload + '"MATCH (s) WHERE ID(s) = '+filter.columnValue +' RETURN s",';
				
			}
			else if (cName != null && cName.equals('Born')){
				
				//This section used to apply filters to the external object's tab
				payload = payload + '"MATCH (s) WHERE s.born '+ Operator + ' ' + filter.columnValue +' RETURN s",';
				
			}else{ 
				
				// in the case of no specific PRIMARY filters, and where an ORDER has been specified
				// then look for secondary filters 
				
				if(c.tableSelection.order != null){
					 
					//This section used for query of most recent items on the external object's tab 
					if (c.tableSelection.filter.subfilters != null && c.tableSelection.filter.type == DataSource.FilterType.OR_) 
					{
						//this section should be re-engineered to support multiple sub queries, if necessary
						payload = payload + '"MATCH (s) WHERE ID(s) = '+filter.subfilters[0].columnValue +' RETURN s",';
					}
					else if (c.tableSelection.filter.subfilters == null )
					{
						//TODO - add sort ASC
							//&& c.tableSelection.order == DataSource.OrderDirection.ASCENDING 
						payload = payload + '"MATCH (s) WHERE ID(s) = '+filter.columnValue +' RETURN s ORDER BY s.born",';
						//call_url = url + '/api/'+ entity + 's' + addPagingFilters(offset, maxResults, true) + addSortFilters(c.tableSelection.order, false);					
					}
					else if (c.tableSelection.filter.subfilters == null  )
					{
						//TODO: Add sort DESC
						//&& c.tableSelection.order == DataSource.OrderDirection.DESCENDING
						payload = payload + '"MATCH (s) WHERE ID(s) = '+filter.columnValue +' RETURN s ORDER BY s.born DESC",';
						//call_url = url + '/api/'+ entity + 's' + addPagingFilters(offset, maxResults, true) + addSortFilters(c.tableSelection.order, false);					
					}
				}else{
					
					//payload = payload + '"MATCH (n {name:"'+'  SAMPLE '+'"}) RETURN n",';
					//call_url = url+'/api/'+entity+'s' + addPagingFilters(offset, maxResults, true);
				}

				//call_url = url+'/api/'+entity+'s' + addPagingFilters(offset, maxResults, true);
			}
			
		}

		//finish the rest call by adding the typical parameters
		payload = payload + '"parameters": {}, "resultDataContents": [ "row", "graph" ], "includeStats": true }]}"';

		// calling external service to get data
        HttpResponse response = getResponse(payload);
	
		//parse the JSON using an JSONtoApex class: GraphQLParser
		GraphQLParser.InnerGraphQLParser gqlp =  GraphQLParser.parse(response.getBody());
		
		List<Map<String, Object>> rows = new List<Map<String, Object>>();
		
		// multiple rows
		if(gqlp.results[0].data.size() >= 1){
		
			List<Object> m = (List<Object>) gqlp.results[0].data; 
			
			//cycle through the results
			for(Integer i=0; i <m.size(); i++ ){
				
				try{
					//extract a row of results
				    rows.add(createRow(m[i], display_url));
				}catch (Exception e)
				{
					System.Debug('Error: '+e);  
				}
			}
		}else {
			System.debug('no rows returned from query');
		}
		
		//send the data back out to salesforce
		return DataSource.TableResult.get(true, null, c.tableSelection.tableSelected, rows);
	}



	// ************************** Helper Functions **************************
	// Adding Sorting for limits
	private string addSortFilters(List<DataSource.Order> order, Boolean isFirstFilter){
		string retFilter = '';
		
		if(order == null) return '';

		if(order.size() == 1){
			// External Id doesn't exists in external system. Replace with 'id' for sort
			if(order[0].columnName == 'ExternalId'){
				retFilter = 'filter[order]=id' + '%20' + getDirection(order[0].direction);
			}
			else{
				retFilter = 'filter[order]=' + order[0].columnName + '%20' + getDirection(order[0].direction);
			}

			if(isFirstFilter == false){
				retFilter = '&' + retFilter;
			}
			else{
				retFilter = '?' + retFilter;
			}
		}
		
		return retFilter;
	}

	// Getting sort direction
	private string getDirection(DataSource.OrderDirection d){
		if(d == DataSource.OrderDirection.ASCENDING)
			return 'ASC';
		else
			return 'DESC';
	}

	// Adds filter for limits and paging
	private string addPagingFilters(Integer offset, Integer maxResults, Boolean isFirstFilter){
		if(maxResults <= 0 )
			return ''; 
		
		if(isFirstFilter == true){
			return '?filter[limit]='+maxResults+'&filter[skip]='+offset;	
		}
		return 'filter[limit]='+maxResults+'&filter[skip]='+offset;
	}

	// Creates rows from JSON data
	public Map<String, Object> createRow(Object item, string DisplayUrl){ 
            
            //ceate a temp var to hold the first level of parsed results
            Map<String, Object> results = new Map<String, Object>();
		
			//put the data back into a JSONtoAPEX class: GraphQLParser.Data
			GraphQLParser.Data d = (GraphQLParser.Data) item;
			
			results.put('Born',d.graph.nodes[0].properties.born);
			results.put('Name',d.graph.nodes[0].properties.name);
			results.put('ExternalId',d.graph.nodes[0].id);
						          
            return results;
            
        }
 
	private HttpResponse getResponse(String payload) {
    
	    Http httpProtocol = new Http();
	    HttpRequest request = new HttpRequest();
	    
	    //set auth header
	    System.Debug('username:password: ' + connectionInfo.username + ':' + connectionInfo.password);
	    Blob headerValue = Blob.valueOf(connectionInfo.username + ':' + connectionInfo.password);
		String authorizationHeader = 'Basic ' + EncodingUtil.base64Encode(headerValue);
	    System.Debug('authorizationHeader: ' + authorizationHeader);
	    
	    request.setEndPoint(url);
	    request.setMethod('POST');
	    request.setHeader('Accept', 'application/json, text/plain, */*');
	    request.setHeader('X-stream', 'true');
	    request.setHeader('Content-Type', 'application/json;charset=utf-8');
	    request.setHeader('Authorization', authorizationHeader);
	    request.setBody(payload);
	    
	    System.Debug('request: ' + request.toString());
	    
	    
	    HttpResponse response = new HttpResponse();
	    
	    try{
	    		response = httpProtocol.send(request);
	    } catch(exception e)
	    {
	    		System.Debug('bad send/response: ' + e.getMessage());
	    }
	    
	    return response;
	}

}